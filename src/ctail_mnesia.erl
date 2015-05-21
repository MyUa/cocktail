-module(ctail_mnesia).
-behaviour(ctail_backend).

-include_lib("stdlib/include/qlc.hrl").

-export([init/0]).
-export([create_table/1, add_table_index/2, dir/0, destroy/0]).
-export([next_id/2, put/1, delete/0]).
-export([get/2, index/3, all/1, count/1]).

%% custom functions
-export([join/1, change_storage/2]).

context() -> 
  ctail:config(mnesia_context, async_dirty).

init() -> 
  mnesia:start().

create_table(Table) ->
  Options = [{attributes, Table#table.fields}],
  Options2 = case proplists:lookup(copy_type, Table#table.options) of
               {copy_type, CopyType} -> [{CopyType, [node()]} | Options];
               _ -> Options
             end,
  case mnesia:create_table(Table#table.name, Options) of
    {atomic, ok} -> ok;
    {aborted, Error} -> {error, Error};
  end.

add_table_index(Record, Field) -> 
  case mnesia:add_table_index(Record, Field) of
    {atomic, ok} -> ok; 
    {aborted, Error} -> {error, Error}; 
  end.

dir() -> 
  mnesia:system_info(local_tables).

destroy() -> 
  [mnesia:delete_table(T) || {_, T} <- ctail:dir()], 
  mnesia:delete_schema([node()]), 
  ok.

next_id(RecordName, Incr) -> 
  mnesia:dirty_update_counter({id_seq, RecordName}, Incr).

put(Records) when is_list(Records) -> 
  void(fun() -> lists:foreach(fun mnesia:write/1, Records) end);
put(Record) -> 
  put([Record]).

delete(Tab, Key) ->
  case mnesia:activity(context(), fun()-> mnesia:delete({Tab, Key}) end) of
    {aborted, Reason} -> {error, Reason};
    {atomic, _Result} -> ok;
    X -> X 
  end.

get(RecordName, Key) ->
  just_one(fun() -> mnesia:read(RecordName, Key) end).

index(Table, Key, Value) ->
  TableInfo = ctail:table(Table),
  Index = string:str(TableInfo#table.fields, [Key]),
  lists:flatten(many(fun() -> mnesia:index_read(Table, Value, Index+1) end)).

all(R) -> 
  lists:flatten(many(fun() -> L = mnesia:all_keys(R), [mnesia:read({R, G}) || G <- L] end)).

count(RecordName) -> 
  mnesia:table_info(RecordName, size).

many(Fun) -> 
  case mnesia:activity(context(), Fun) of 
    {atomic, R} -> R; 
    X -> X 
  end.

void(Fun) -> 
  case mnesia:activity(context(),Fun) of 
    {atomic, ok} -> ok; 
    {aborted, Error} -> {error, Error}; 
    X -> X 
  end.

exec(Q) -> 
  F = fun() -> qlc:e(Q) end, 
  {atomic, Val} = mnesia:activity(context(), F), Val.

just_one(Fun) ->
  case mnesia:activity(context(),Fun) of
    {atomic, []} -> {error, not_found};
    {atomic, [R]} -> {ok, R};
    {atomic, [_|_]} -> {error, duplicated};
    [] -> {error, not_found};
    [R] -> {ok, R};
    [_|_] -> {error, duplicated};
    Error -> Error
  end.

join([]) -> 
  mnesia:change_table_copy_type(schema, node(), ctail:config(mnesia_media, disc_copies)),
  mnesia:create_schema([node()]),
  ctail:create_schema(ctail_mnesia),
  mnesia:wait_for_tables([ T#table.name || T <- ctail:tables()], infinity);

join(Node) ->
  mnesia:change_config(extra_db_nodes, [Node]),
  mnesia:change_table_copy_type(schema, node(), ctail:config(mnesia_media, disc_copies)),

  [{Tb, mnesia:add_table_copy(Tb, node(), Type)} || 
   {Tb, [{N, Type}]} <- [{T, mnesia:table_info(T, where_to_commit)} || 
                         T <- mnesia:system_info(tables)], Node==N].

change_storage(Table, Type) -> 
  mnesia:change_table_copy_type(Table, node(), Type).
