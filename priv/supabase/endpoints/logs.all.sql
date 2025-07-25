with edge_logs as (
select 
  t.timestamp,
  t.id, 
  t.event_message, 
  t.metadata 
from `cloudflare.logs.prod` as t
  cross join unnest(metadata) as m
where
  -- order of the where clauses matters
  -- project then timestamp then everything else
  t.project = @project
  AND CASE WHEN COALESCE(@iso_timestamp_start, '') = '' THEN  TRUE ELSE  cast(t.timestamp as timestamp) > cast(@iso_timestamp_start as timestamp) END
  AND CASE WHEN COALESCE(@iso_timestamp_end, '') = '' THEN TRUE ELSE cast(t.timestamp as timestamp) <= cast(@iso_timestamp_end as timestamp) END
order by
  cast(t.timestamp as timestamp) desc
),

postgres_logs as (
  select 
  t.timestamp,
  t.id, 
  t.event_message, 
  t.metadata
from `postgres.logs` as t
where
  -- order of the where clauses matters
  -- project then timestamp then everything else
  t.project = @project
  AND CASE WHEN COALESCE(@iso_timestamp_start, '') = '' THEN  TRUE ELSE  cast(t.timestamp as timestamp) > cast(@iso_timestamp_start as timestamp) END
  AND CASE WHEN COALESCE(@iso_timestamp_end, '') = '' THEN TRUE ELSE cast(t.timestamp as timestamp) <= cast(@iso_timestamp_end as timestamp) END
  order by cast(t.timestamp as timestamp) desc
),

function_edge_logs as (
select 
  t.timestamp,
  t.id, 
  t.event_message, 
  t.metadata 
from `deno-relay-logs` as t
  cross join unnest(t.metadata) as m
where
  CASE WHEN COALESCE(@iso_timestamp_start, '') = '' THEN  TRUE ELSE  cast(t.timestamp as timestamp) > cast(@iso_timestamp_start as timestamp) END
  AND CASE WHEN COALESCE(@iso_timestamp_end, '') = '' THEN TRUE ELSE cast(t.timestamp as timestamp) <= cast(@iso_timestamp_end as timestamp) END
  and m.project_ref = @project
order by cast(t.timestamp as timestamp) desc
),

function_logs as (
select 
  t.timestamp,
  t.id, 
  t.event_message, 
  t.metadata 
from `deno-subhosting-events` as t
  cross join unnest(t.metadata) as m
where
  -- order of the where clauses matters
  -- project then timestamp then everything else
  m.project_ref = @project
  AND CASE WHEN COALESCE(@iso_timestamp_start, '') = '' THEN  TRUE ELSE  cast(t.timestamp as timestamp) > cast(@iso_timestamp_start as timestamp) END
  AND CASE WHEN COALESCE(@iso_timestamp_end, '') = '' THEN TRUE ELSE cast(t.timestamp as timestamp) <= cast(@iso_timestamp_end as timestamp) END
order by cast(t.timestamp as timestamp) desc
),

auth_logs as (
select 
  t.timestamp,
  t.id, 
  t.event_message, 
  t.metadata 
from `gotrue.logs.prod` as t
  cross join unnest(t.metadata) as m
where
  -- order of the where clauses matters
  -- project then timestamp then everything else
  -- m.project = @project
  t.project = @project
  AND CASE WHEN COALESCE(@iso_timestamp_start, '') = '' THEN  TRUE ELSE  cast(t.timestamp as timestamp) > cast(@iso_timestamp_start as timestamp) END
  AND CASE WHEN COALESCE(@iso_timestamp_end, '') = '' THEN TRUE ELSE cast(t.timestamp as timestamp) <= cast(@iso_timestamp_end as timestamp) END
order by cast(t.timestamp as timestamp) desc
),

realtime_logs as (
select 
  t.timestamp,
  t.id, 
  t.event_message, 
  t.metadata 
from `realtime.logs.prod` as t
  cross join unnest(t.metadata) as m
where
  m.project = @project 
  AND CASE WHEN COALESCE(@iso_timestamp_start, '') = '' THEN  TRUE ELSE  cast(t.timestamp as timestamp) > cast(@iso_timestamp_start as timestamp) END
  AND CASE WHEN COALESCE(@iso_timestamp_end, '') = '' THEN TRUE ELSE cast(t.timestamp as timestamp) <= cast(@iso_timestamp_end as timestamp) END
order by cast(t.timestamp as timestamp) desc
),

storage_logs as (
select 
  t.timestamp,
  t.id, 
  t.event_message, 
  t.metadata 
from `storage.logs.prod.2` as t
  cross join unnest(t.metadata) as m
where
  m.project = @project
  AND CASE WHEN COALESCE(@iso_timestamp_start, '') = '' THEN  TRUE ELSE  cast(t.timestamp as timestamp) > cast(@iso_timestamp_start as timestamp) END
  AND CASE WHEN COALESCE(@iso_timestamp_end, '') = '' THEN TRUE ELSE cast(t.timestamp as timestamp) <= cast(@iso_timestamp_end as timestamp) END
order by cast(t.timestamp as timestamp) desc
),

postgrest_logs as (
select 
  t.timestamp,
  t.id, 
  t.event_message, 
  t.metadata 
from `postgREST.logs.prod` as t
  cross join unnest(t.metadata) as m
where
  CASE WHEN COALESCE(@iso_timestamp_start, '') = '' THEN  TRUE ELSE  cast(t.timestamp as timestamp) > cast(@iso_timestamp_start as timestamp) END
  AND CASE WHEN COALESCE(@iso_timestamp_end, '') = '' THEN TRUE ELSE cast(t.timestamp as timestamp) <= cast(@iso_timestamp_end as timestamp) END
  AND t.project = @project
order by cast(t.timestamp as timestamp) desc
),

pgbouncer_logs as (
select 
  t.timestamp,
  t.id, 
  t.event_message, 
  t.metadata 
from `pgbouncer.logs.prod` as t
  cross join unnest(t.metadata) as m
where
  CASE WHEN COALESCE(@iso_timestamp_start, '') = '' THEN  TRUE ELSE  cast(t.timestamp as timestamp) > cast(@iso_timestamp_start as timestamp) END
  AND CASE WHEN COALESCE(@iso_timestamp_end, '') = '' THEN TRUE ELSE cast(t.timestamp as timestamp) <= cast(@iso_timestamp_end as timestamp) END
  AND t.project = @project
order by cast(t.timestamp as timestamp) desc
)

SELECT id, timestamp, event_message, metadata
FROM edge_logs
LIMIT 100