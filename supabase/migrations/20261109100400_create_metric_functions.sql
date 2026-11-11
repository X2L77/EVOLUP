-- Data engine of EVOLUP (SPEC_PROJECT.md §6 and §8).
--
-- Writes: public.record_metric_entry and public.correct_metric_day are the
-- only way to create or change a daily aggregate. They are SECURITY DEFINER
-- because clients have no INSERT/UPDATE privilege on the aggregates: with
-- direct writes, a client could forge counters or fingerprints and bypass the
-- validation and the duplicate detection. Each of them runs with an empty
-- search_path, qualifies every name, checks auth.uid() and the ownership of
-- the tracked metric itself, and can only be executed by `authenticated`.
--
-- Reads: SECURITY INVOKER functions and a security_invoker view, so RLS
-- applies to every row they touch. Grouping by week or month happens here,
-- never on the phone.
--
-- Errors are raised with SQLSTATE 22023 (HTTP 400 through the Data API) or
-- 42501, and a stable code as message (listed in SPEC_PROJECT.md §8.3).

-- Helpers ---------------------------------------------------------------------

-- Requests sent by the coach-chat Edge Function carry this header (defence in
-- depth: Polomix must never write; the function has no write path either).
create or replace function private.request_is_from_coach()
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce(
    (
      nullif(pg_catalog.current_setting('request.headers', true), '')::jsonb
      ->> 'x-evolup-actor'
    ) = 'polomix',
    false
  );
$$;

create or replace function private.assert_can_write(p_user uuid)
returns void
language plpgsql
stable
set search_path = ''
as $$
begin
  if p_user is null then
    raise exception using errcode = '42501', message = 'not_authenticated';
  end if;
  if private.request_is_from_coach() then
    raise exception using errcode = '42501', message = 'coach_cannot_write';
  end if;
end;
$$;

-- Value of a day (or of a period) according to the metric's aggregation.
-- For an average, the period value is weighted: sum of the sums divided by
-- the total number of entries, never an average of daily averages.
create or replace function private.metric_daily_value(
  p_aggregation text,
  p_sum numeric,
  p_count bigint,
  p_min numeric,
  p_max numeric,
  p_last numeric
)
returns numeric
language sql
immutable
set search_path = ''
as $$
  select case p_aggregation
    when 'average' then p_sum / nullif(p_count, 0)
    when 'sum' then p_sum
    when 'max' then p_max
    when 'min' then p_min
    when 'last' then p_last
  end;
$$;

-- 64-bit fingerprint of a normalised value merged into a given day. The
-- value is normalised by the caller (rounded to the storage scale) and
-- written without trailing zeros, so 8, 8.0 and 8.00 give the same hash.
create or replace function private.metric_value_fingerprint(
  p_user_metric_id uuid,
  p_local_date date,
  p_value numeric
)
returns bigint
language sql
immutable
set search_path = ''
as $$
  select (
    'x' || pg_catalog.left(
      pg_catalog.encode(
        pg_catalog.sha256(
          pg_catalog.convert_to(
            p_user_metric_id::text
              || '|' || (p_local_date - date '2000-01-01')::text
              || '|' || pg_catalog.trim_scale(p_value)::text,
            'UTF8'
          )
        ),
        'hex'
      ),
      16
    )
  )::bit(64)::bigint;
$$;

-- Checks a value expressed in the metric's storage unit and returns it
-- normalised.
create or replace function private.checked_metric_value(
  p_metric public.metric_catalog,
  p_value numeric,
  p_unit text
)
returns numeric
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_value numeric;
begin
  if p_unit is distinct from p_metric.storage_unit then
    raise exception using errcode = '22023', message = 'unit_mismatch';
  end if;
  if p_value is null
    or p_value = 'NaN'::numeric
    or p_value in ('Infinity'::numeric, '-Infinity'::numeric) then
    raise exception using errcode = '22023', message = 'value_invalid';
  end if;
  v_value := pg_catalog.round(p_value, p_metric.storage_scale);
  if v_value <> p_value then
    raise exception using errcode = '22023', message = 'value_precision';
  end if;
  if (p_metric.min_value is not null and v_value < p_metric.min_value)
    or (p_metric.max_value is not null and v_value > p_metric.max_value) then
    raise exception using errcode = '22023', message = 'value_out_of_range';
  end if;
  return v_value;
end;
$$;

-- The local day must not be in the future where the user is, and the zone
-- must be an IANA zone (the profile's zone is already validated).
create or replace function private.assert_valid_local_date(
  p_user uuid,
  p_local_date date,
  p_timezone text
)
returns void
language plpgsql
stable
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.profiles
    where user_id = p_user and timezone = p_timezone
  ) and not private.is_valid_timezone(p_timezone) then
    raise exception using errcode = '22023', message = 'invalid_timezone';
  end if;
  if p_local_date < date '1900-01-01' then
    raise exception using errcode = '22023', message = 'date_too_old';
  end if;
  if p_local_date > (pg_catalog.now() at time zone p_timezone)::date then
    raise exception using errcode = '22023', message = 'date_in_future';
  end if;
end;
$$;

create or replace function private.aggregate_json(
  p_row public.metric_daily_aggregates,
  p_aggregation text
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'user_metric_id', p_row.user_metric_id,
    'local_date', p_row.local_date,
    'timezone_name', p_row.timezone_name,
    'sample_count', p_row.sample_count,
    'value_sum', p_row.value_sum,
    'value_min', p_row.value_min,
    'value_max', p_row.value_max,
    'value_last', p_row.value_last,
    'daily_value', private.metric_daily_value(
      p_aggregation, p_row.value_sum, p_row.sample_count, p_row.value_min,
      p_row.value_max, p_row.value_last
    )
  );
$$;

create or replace function private.assert_period(p_from date, p_to date)
returns void
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_from is null or p_to is null or p_from > p_to
    or p_from < date '1900-01-01' or p_to - p_from > 36600 then
    raise exception using errcode = '22023', message = 'invalid_period';
  end if;
end;
$$;

revoke all on function private.request_is_from_coach()
  from public, anon, authenticated, service_role;
revoke all on function private.assert_can_write(uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.metric_daily_value(
  text, numeric, bigint, numeric, numeric, numeric
) from public, anon, authenticated, service_role;
revoke all on function private.metric_value_fingerprint(uuid, date, numeric)
  from public, anon, authenticated, service_role;
revoke all on function private.checked_metric_value(
  public.metric_catalog, numeric, text
) from public, anon, authenticated, service_role;
revoke all on function private.assert_valid_local_date(uuid, date, text)
  from public, anon, authenticated, service_role;
revoke all on function private.aggregate_json(
  public.metric_daily_aggregates, text
) from public, anon, authenticated, service_role;
revoke all on function private.assert_period(date, date)
  from public, anon, authenticated, service_role;
-- Used by the SECURITY INVOKER reads below.
grant execute on function private.metric_daily_value(
  text, numeric, bigint, numeric, numeric, numeric
) to authenticated;
grant execute on function private.assert_period(date, date) to authenticated;

-- Writes ----------------------------------------------------------------------

-- Merges one validated entry into its daily aggregate, atomically.
--
-- Result: {"status": "recorded" | "duplicate" | "already_recorded",
--          "aggregate": {...}}
--   recorded          the value was added to the day;
--   duplicate         the same normalised value is already part of this day
--                     (same user, metric and local day): nothing changes;
--   already_recorded  this idempotency key was already merged (the client
--                     retried a request that had succeeded): nothing changes.
--
-- Concurrency: the day's row is created with INSERT ... ON CONFLICT DO
-- NOTHING, otherwise locked with SELECT ... FOR UPDATE before it is read and
-- updated, so simultaneous entries are applied one after the other and none
-- is lost.
create or replace function public.record_metric_entry(
  p_user_metric_id uuid,
  p_value numeric,
  p_unit text,
  p_local_date date,
  p_timezone text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_tracked public.user_metrics%rowtype;
  v_metric public.metric_catalog%rowtype;
  v_value numeric;
  v_fingerprint bigint;
  v_row public.metric_daily_aggregates%rowtype;
  v_status text;
  v_attempt integer := 0;
begin
  perform private.assert_can_write(v_user);
  if p_user_metric_id is null or p_value is null or p_unit is null
    or p_local_date is null or p_timezone is null
    or p_idempotency_key is null then
    raise exception using errcode = '22023', message = 'missing_parameter';
  end if;

  select * into v_tracked
  from public.user_metrics
  where id = p_user_metric_id and user_id = v_user;
  if not found then
    raise exception using errcode = '22023', message = 'metric_not_tracked';
  end if;
  if not v_tracked.is_active then
    raise exception using errcode = '22023', message = 'metric_not_active';
  end if;
  select * into v_metric
  from public.metric_catalog
  where id = v_tracked.metric_catalog_id;
  if not v_metric.is_active then
    raise exception using errcode = '22023', message = 'metric_retired';
  end if;

  v_value := private.checked_metric_value(v_metric, p_value, p_unit);
  perform private.assert_valid_local_date(v_user, p_local_date, p_timezone);
  v_fingerprint := private.metric_value_fingerprint(
    p_user_metric_id, p_local_date, v_value
  );

  loop
    v_attempt := v_attempt + 1;

    insert into public.metric_daily_aggregates (
      user_id, user_metric_id, local_date, timezone_name, sample_count,
      value_sum, value_min, value_max, value_last, entry_fingerprints,
      request_keys
    )
    values (
      v_user, p_user_metric_id, p_local_date, p_timezone, 1,
      v_value, v_value, v_value, v_value, array[v_fingerprint],
      array[p_idempotency_key]
    )
    on conflict (user_metric_id, local_date) do nothing
    returning * into v_row;
    if found then
      v_status := 'recorded';
      exit;
    end if;

    select * into v_row
    from public.metric_daily_aggregates
    where user_metric_id = p_user_metric_id and local_date = p_local_date
    for update;
    if found then
      if p_idempotency_key = any (v_row.request_keys) then
        v_status := 'already_recorded';
      elsif v_fingerprint = any (v_row.entry_fingerprints) then
        v_status := 'duplicate';
      else
        if v_row.sample_count >= 200 then
          raise exception using errcode = '22023', message = 'daily_entry_limit';
        end if;
        if v_metric.daily_sum_max is not null
          and v_row.value_sum + v_value > v_metric.daily_sum_max then
          raise exception using errcode = '22023', message = 'daily_sum_exceeded';
        end if;
        update public.metric_daily_aggregates
        set
          sample_count = v_row.sample_count + 1,
          value_sum = v_row.value_sum + v_value,
          value_min = least(v_row.value_min, v_value),
          value_max = greatest(v_row.value_max, v_value),
          value_last = v_value,
          entry_fingerprints = v_row.entry_fingerprints || v_fingerprint,
          request_keys = (v_row.request_keys || p_idempotency_key)[
            greatest(1, cardinality(v_row.request_keys) - 198):
          ],
          updated_at = pg_catalog.now()
        where id = v_row.id
        returning * into v_row;
        v_status := 'recorded';
      end if;
      exit;
    end if;

    -- The row was deleted between the insert and the lock: try again.
    if v_attempt >= 3 then
      raise exception using errcode = '40001', message = 'concurrent_update';
    end if;
  end loop;

  return pg_catalog.jsonb_build_object(
    'status', v_status,
    'aggregate', private.aggregate_json(v_row, v_metric.aggregation)
  );
end;
$$;

-- Replaces an existing day by a single corrected value. Individual entries
-- are not stored, so a merged entry cannot be edited on its own: the day
-- becomes one entry (sample_count = 1) whose fingerprint is the new value.
create or replace function public.correct_metric_day(
  p_user_metric_id uuid,
  p_local_date date,
  p_value numeric,
  p_unit text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_metric public.metric_catalog%rowtype;
  v_value numeric;
  v_row public.metric_daily_aggregates%rowtype;
begin
  perform private.assert_can_write(v_user);
  if p_user_metric_id is null or p_local_date is null or p_value is null
    or p_unit is null then
    raise exception using errcode = '22023', message = 'missing_parameter';
  end if;

  select c.* into v_metric
  from public.user_metrics um
  join public.metric_catalog c on c.id = um.metric_catalog_id
  where um.id = p_user_metric_id and um.user_id = v_user;
  if not found then
    raise exception using errcode = '22023', message = 'metric_not_tracked';
  end if;

  v_value := private.checked_metric_value(v_metric, p_value, p_unit);
  if v_metric.daily_sum_max is not null and v_value > v_metric.daily_sum_max then
    raise exception using errcode = '22023', message = 'daily_sum_exceeded';
  end if;

  update public.metric_daily_aggregates
  set
    sample_count = 1,
    value_sum = v_value,
    value_min = v_value,
    value_max = v_value,
    value_last = v_value,
    entry_fingerprints = array[
      private.metric_value_fingerprint(p_user_metric_id, p_local_date, v_value)
    ],
    updated_at = pg_catalog.now()
  where user_metric_id = p_user_metric_id
    and local_date = p_local_date
    and user_id = v_user
  returning * into v_row;
  if not found then
    raise exception using errcode = '22023', message = 'day_not_found';
  end if;

  return pg_catalog.jsonb_build_object(
    'status', 'corrected',
    'aggregate', private.aggregate_json(v_row, v_metric.aggregation)
  );
end;
$$;

revoke all on function public.record_metric_entry(
  uuid, numeric, text, date, text, uuid
) from public, anon, authenticated, service_role;
revoke all on function public.correct_metric_day(uuid, date, numeric, text)
  from public, anon, authenticated, service_role;
grant execute on function public.record_metric_entry(
  uuid, numeric, text, date, text, uuid
) to authenticated;
grant execute on function public.correct_metric_day(uuid, date, numeric, text)
  to authenticated;

-- Reads -----------------------------------------------------------------------

-- One row per recorded day with its value according to the metric's
-- aggregation. No fingerprint and no idempotency key.
create or replace view public.metric_daily_values
with (security_invoker = true)
as
select
  a.id,
  a.user_id,
  a.user_metric_id,
  a.local_date,
  a.timezone_name,
  a.sample_count,
  a.value_sum,
  a.value_min,
  a.value_max,
  a.value_last,
  private.metric_daily_value(
    c.aggregation, a.value_sum, a.sample_count, a.value_min, a.value_max,
    a.value_last
  ) as daily_value,
  a.created_at,
  a.updated_at
from public.metric_daily_aggregates a
join public.user_metrics um on um.id = a.user_metric_id
join public.metric_catalog c on c.id = um.metric_catalog_id;

revoke all on table public.metric_daily_values
  from public, anon, authenticated, service_role;
grant select on table public.metric_daily_values to authenticated;

-- Points of a chart: one per day, ISO week (Monday) or month. 'auto' keeps
-- every chart under ~120 points: days up to 120 days, weeks up to two years,
-- months beyond.
create or replace function public.get_metric_history(
  p_user_metric_id uuid,
  p_from date,
  p_to date,
  p_bucket text default 'auto'
)
returns table (
  bucket text,
  bucket_start date,
  value numeric,
  sample_count bigint,
  days_count bigint,
  value_min numeric,
  value_max numeric,
  first_date date,
  last_date date
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_bucket text;
  v_aggregation text;
begin
  perform private.assert_period(p_from, p_to);
  v_bucket := case
    when p_bucket is distinct from 'auto' then p_bucket
    when p_to - p_from <= 120 then 'day'
    when p_to - p_from <= 731 then 'week'
    else 'month'
  end;
  if v_bucket is null or v_bucket not in ('day', 'week', 'month') then
    raise exception using errcode = '22023', message = 'invalid_bucket';
  end if;
  if (v_bucket = 'day' and p_to - p_from > 1000)
    or (v_bucket = 'week' and p_to - p_from > 7000) then
    raise exception using errcode = '22023', message = 'too_many_points';
  end if;

  select c.aggregation into v_aggregation
  from public.user_metrics um
  join public.metric_catalog c on c.id = um.metric_catalog_id
  where um.id = p_user_metric_id;
  if not found then
    return;
  end if;

  return query
  select
    v_bucket,
    b.bucket_start,
    private.metric_daily_value(
      v_aggregation,
      sum(a.value_sum),
      sum(a.sample_count),
      min(a.value_min),
      max(a.value_max),
      (array_agg(a.value_last order by a.local_date desc))[1]
    ),
    sum(a.sample_count),
    count(*),
    min(a.value_min),
    max(a.value_max),
    min(a.local_date),
    max(a.local_date)
  from public.metric_daily_aggregates a
  cross join lateral (
    select case v_bucket
      when 'day' then a.local_date
      when 'week' then pg_catalog.date_trunc('week', a.local_date::timestamp)::date
      else pg_catalog.date_trunc('month', a.local_date::timestamp)::date
    end as bucket_start
  ) b
  where a.user_metric_id = p_user_metric_id
    and a.local_date between p_from and p_to
  group by b.bucket_start
  order by b.bucket_start;
end;
$$;

-- Summary of a period and of the whole history of a tracked metric.
--   period.value           the period's value by aggregation (weighted
--                          average, total, best, lowest, last);
--   period.per_day_average for sum metrics only: total / recorded days;
--   record                 best single entry ever, only for metrics with a
--                          record direction;
--   trend                  least-squares slope of the daily values per day,
--                          only from 5 recorded days in the period.
create or replace function public.get_metric_statistics(
  p_user_metric_id uuid,
  p_from date,
  p_to date
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_aggregation text;
  v_direction text;
  v_period jsonb;
  v_all_time jsonb;
  v_latest jsonb;
  v_record jsonb;
  v_trend jsonb;
begin
  perform private.assert_period(p_from, p_to);
  select c.aggregation, c.record_direction into v_aggregation, v_direction
  from public.user_metrics um
  join public.metric_catalog c on c.id = um.metric_catalog_id
  where um.id = p_user_metric_id;
  if not found then
    return null;
  end if;

  select pg_catalog.jsonb_build_object(
    'from', p_from,
    'to', p_to,
    'value', private.metric_daily_value(
      v_aggregation, sum(a.value_sum), sum(a.sample_count), min(a.value_min),
      max(a.value_max), (array_agg(a.value_last order by a.local_date desc))[1]
    ),
    'per_day_average', case
      when v_aggregation = 'sum' then sum(a.value_sum) / nullif(count(*), 0)
    end,
    'days_count', count(*),
    'sample_count', coalesce(sum(a.sample_count), 0),
    'first_date', min(a.local_date),
    'last_date', max(a.local_date),
    'value_min', min(a.value_min),
    'value_max', max(a.value_max)
  ) into v_period
  from public.metric_daily_aggregates a
  where a.user_metric_id = p_user_metric_id
    and a.local_date between p_from and p_to;

  select pg_catalog.jsonb_build_object(
    'value', private.metric_daily_value(
      v_aggregation, sum(a.value_sum), sum(a.sample_count), min(a.value_min),
      max(a.value_max), (array_agg(a.value_last order by a.local_date desc))[1]
    ),
    'days_count', count(*),
    'sample_count', coalesce(sum(a.sample_count), 0),
    'first_date', min(a.local_date),
    'last_date', max(a.local_date)
  ) into v_all_time
  from public.metric_daily_aggregates a
  where a.user_metric_id = p_user_metric_id;

  select pg_catalog.jsonb_build_object(
    'local_date', a.local_date,
    'value', private.metric_daily_value(
      v_aggregation, a.value_sum, a.sample_count, a.value_min, a.value_max,
      a.value_last
    ),
    'sample_count', a.sample_count
  ) into v_latest
  from public.metric_daily_aggregates a
  where a.user_metric_id = p_user_metric_id
  order by a.local_date desc
  limit 1;

  if v_direction = 'higher' then
    select pg_catalog.jsonb_build_object(
      'value', a.value_max, 'local_date', a.local_date
    ) into v_record
    from public.metric_daily_aggregates a
    where a.user_metric_id = p_user_metric_id
    order by a.value_max desc, a.local_date
    limit 1;
  elsif v_direction = 'lower' then
    select pg_catalog.jsonb_build_object(
      'value', a.value_min, 'local_date', a.local_date
    ) into v_record
    from public.metric_daily_aggregates a
    where a.user_metric_id = p_user_metric_id
    order by a.value_min, a.local_date
    limit 1;
  end if;

  select case when count(*) >= 5 then pg_catalog.jsonb_build_object(
    'slope_per_day', regr_slope(d.value, d.day_index),
    'r2', regr_r2(d.value, d.day_index),
    'points', count(*)
  ) end into v_trend
  from (
    select
      private.metric_daily_value(
        v_aggregation, a.value_sum, a.sample_count, a.value_min, a.value_max,
        a.value_last
      ) as value,
      (a.local_date - p_from)::double precision as day_index
    from public.metric_daily_aggregates a
    where a.user_metric_id = p_user_metric_id
      and a.local_date between p_from and p_to
  ) d;

  return pg_catalog.jsonb_build_object(
    'aggregation', v_aggregation,
    'record_direction', v_direction,
    'period', v_period,
    'all_time', v_all_time,
    'latest', v_latest,
    'record', v_record,
    'trend', v_trend
  );
end;
$$;

-- Compares two periods of the same metric (a = reference, b = compared).
-- The difference is only given when each period has at least 3 recorded
-- days; otherwise "comparable" is false.
create or replace function public.compare_metric_periods(
  p_user_metric_id uuid,
  p_a_from date,
  p_a_to date,
  p_b_from date,
  p_b_to date
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_aggregation text;
  v_a jsonb;
  v_b jsonb;
  v_a_value numeric;
  v_b_value numeric;
  v_comparable boolean;
  c_min_days constant integer := 3;
begin
  perform private.assert_period(p_a_from, p_a_to);
  perform private.assert_period(p_b_from, p_b_to);
  select c.aggregation into v_aggregation
  from public.user_metrics um
  join public.metric_catalog c on c.id = um.metric_catalog_id
  where um.id = p_user_metric_id;
  if not found then
    return null;
  end if;

  select pg_catalog.jsonb_build_object(
    'from', p_a_from,
    'to', p_a_to,
    'value', private.metric_daily_value(
      v_aggregation, sum(a.value_sum), sum(a.sample_count), min(a.value_min),
      max(a.value_max), (array_agg(a.value_last order by a.local_date desc))[1]
    ),
    'days_count', count(*),
    'sample_count', coalesce(sum(a.sample_count), 0)
  ) into v_a
  from public.metric_daily_aggregates a
  where a.user_metric_id = p_user_metric_id
    and a.local_date between p_a_from and p_a_to;

  select pg_catalog.jsonb_build_object(
    'from', p_b_from,
    'to', p_b_to,
    'value', private.metric_daily_value(
      v_aggregation, sum(a.value_sum), sum(a.sample_count), min(a.value_min),
      max(a.value_max), (array_agg(a.value_last order by a.local_date desc))[1]
    ),
    'days_count', count(*),
    'sample_count', coalesce(sum(a.sample_count), 0)
  ) into v_b
  from public.metric_daily_aggregates a
  where a.user_metric_id = p_user_metric_id
    and a.local_date between p_b_from and p_b_to;

  v_a_value := (v_a ->> 'value')::numeric;
  v_b_value := (v_b ->> 'value')::numeric;
  v_comparable := (v_a ->> 'days_count')::integer >= c_min_days
    and (v_b ->> 'days_count')::integer >= c_min_days;

  return pg_catalog.jsonb_build_object(
    'aggregation', v_aggregation,
    'a', v_a,
    'b', v_b,
    'min_days', c_min_days,
    'comparable', v_comparable,
    'difference', case when v_comparable then v_b_value - v_a_value end,
    'percent_change', case
      when v_comparable and v_a_value <> 0
        then (v_b_value - v_a_value) / abs(v_a_value) * 100
    end
  );
end;
$$;

-- Data of the "Vue d'ensemble" page: every tracked metric (active or not)
-- with its latest day and the last 30 days compared with the 30 days before,
-- "today" being computed in the profile's time zone.
create or replace function public.get_overview()
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_timezone text;
  v_today date;
  c_min_days constant integer := 3;
begin
  if v_user is null then
    raise exception using errcode = '42501', message = 'not_authenticated';
  end if;
  select p.timezone into v_timezone
  from public.profiles p
  where p.user_id = v_user;
  v_timezone := coalesce(v_timezone, 'UTC');
  v_today := (pg_catalog.now() at time zone v_timezone)::date;

  return pg_catalog.jsonb_build_object(
    'today', v_today,
    'timezone', v_timezone,
    'min_days', c_min_days,
    'days_recorded', (
      select count(distinct a.local_date)
      from public.metric_daily_aggregates a
      where a.user_id = v_user
    ),
    'entries_count', (
      select coalesce(sum(a.sample_count), 0)
      from public.metric_daily_aggregates a
      where a.user_id = v_user
    ),
    'first_date', (
      select min(a.local_date)
      from public.metric_daily_aggregates a
      where a.user_id = v_user
    ),
    'metrics', coalesce((
      select pg_catalog.jsonb_agg(m.item order by m.is_favorite desc,
        m.sort_order, m.category_sort, m.metric_sort)
      from (
        select
          um.is_favorite,
          um.sort_order,
          cat.sort_order as category_sort,
          c.sort_order as metric_sort,
          pg_catalog.jsonb_build_object(
            'user_metric_id', um.id,
            'metric_catalog_id', um.metric_catalog_id,
            'is_active', um.is_active,
            'is_favorite', um.is_favorite,
            'days_count', stats.days_count,
            'first_date', stats.first_date,
            'latest', latest.item,
            'recent', recent.item,
            'previous', previous.item,
            'comparable', (recent.item ->> 'days_count')::integer >= c_min_days
              and (previous.item ->> 'days_count')::integer >= c_min_days
          ) as item
        from public.user_metrics um
        join public.metric_catalog c on c.id = um.metric_catalog_id
        join public.metric_categories cat on cat.id = c.category_id
        cross join lateral (
          select count(*) as days_count, min(a.local_date) as first_date
          from public.metric_daily_aggregates a
          where a.user_metric_id = um.id
        ) stats
        left join lateral (
          select pg_catalog.jsonb_build_object(
            'local_date', a.local_date,
            'value', private.metric_daily_value(
              c.aggregation, a.value_sum, a.sample_count, a.value_min,
              a.value_max, a.value_last
            ),
            'sample_count', a.sample_count
          ) as item
          from public.metric_daily_aggregates a
          where a.user_metric_id = um.id
          order by a.local_date desc
          limit 1
        ) latest on true
        cross join lateral (
          select pg_catalog.jsonb_build_object(
            'from', v_today - 29,
            'to', v_today,
            'value', private.metric_daily_value(
              c.aggregation, sum(a.value_sum), sum(a.sample_count),
              min(a.value_min), max(a.value_max),
              (array_agg(a.value_last order by a.local_date desc))[1]
            ),
            'days_count', count(*)
          ) as item
          from public.metric_daily_aggregates a
          where a.user_metric_id = um.id
            and a.local_date between v_today - 29 and v_today
        ) recent
        cross join lateral (
          select pg_catalog.jsonb_build_object(
            'from', v_today - 59,
            'to', v_today - 30,
            'value', private.metric_daily_value(
              c.aggregation, sum(a.value_sum), sum(a.sample_count),
              min(a.value_min), max(a.value_max),
              (array_agg(a.value_last order by a.local_date desc))[1]
            ),
            'days_count', count(*)
          ) as item
          from public.metric_daily_aggregates a
          where a.user_metric_id = um.id
            and a.local_date between v_today - 59 and v_today - 30
        ) previous
        where um.user_id = v_user
      ) m
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_metric_history(uuid, date, date, text)
  from public, anon, authenticated, service_role;
revoke all on function public.get_metric_statistics(uuid, date, date)
  from public, anon, authenticated, service_role;
revoke all on function public.compare_metric_periods(
  uuid, date, date, date, date
) from public, anon, authenticated, service_role;
revoke all on function public.get_overview()
  from public, anon, authenticated, service_role;
grant execute on function public.get_metric_history(uuid, date, date, text)
  to authenticated;
grant execute on function public.get_metric_statistics(uuid, date, date)
  to authenticated;
grant execute on function public.compare_metric_periods(
  uuid, date, date, date, date
) to authenticated;
grant execute on function public.get_overview() to authenticated;
