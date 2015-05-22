-ifndef(CTAIL_HRL).
-define(CTAIL_HRL, 1).

-record(schema, {
  name,
  tables=[]
}).

-record(table, {
  name, 
  container=feed, 
  fields=[], 
  keys=[], 
  options=[]
}).

-define(CONTAINER, 
  id, 
  top, 
  count=0
).

-define(ITERATOR(Container), 
  id, 
  version,
  container=Container, 
  feed_id, 
  prev, 
  next
).

-record(interval,  {left, right, name}).
-record(container, {?CONTAINER}).
-record(feed,      {?CONTAINER}).
-record(iterator,  {?ITERATOR(undefined)}).

-endif.
