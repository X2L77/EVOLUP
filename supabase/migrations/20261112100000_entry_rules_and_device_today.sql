-- Corrections of 2026-11-12 (SPEC_PROJECT.md §6.4, §6.6, §6.7, §8; owner's
-- decisions of that day). No table, column or row is changed.
--
-- 1. New entries: the local day must be within the last year (same calendar
--    day one year earlier; 29 February -> 28 February) and never in the
--    future, both in the zone of the entry. Existing older days stay
--    readable, correctable and deletable (correct_metric_day and DELETE do
--    not check the date).
-- 2. record_metric_entry gains p_confirm_duplicate (default false): an
--    identical value on the same day is still reported as 'duplicate', and
--    the user may confirm it is a new measure, which is then counted.
--    Calls with the six former arguments behave as before.
-- 3. get_metric_history refuses the 'day' grouping above 365 calendar days.
-- 4. get_overview gains p_today (default null): the app sends the device's
--    local day; without it (Polomix v5), "today" stays the profile's day.
--
-- record_metric_entry and get_overview change signature: the old function is
-- dropped and the new one created with the same privileges. Defaults keep
-- every existing call (PostgREST named arguments) working.

-- "Today" in an IANA zone. Its own function so that the database tests can
-- pin the clock inside their rolled-back transaction.
create or replace function private.local_today(p_timezone text)
returns date
language sql
stable
set search_path = ''
as $$
  select (pg_catalog.now() at time zone p_timezone)::date;
$$;

revoke all on function private.local_today(text)
  from public, anon, authenticated, service_role;
-- Used by the SECURITY INVOKER get_overview.
grant execute on function private.local_today(text) to authenticated;

-- Earliest local day accepted for a new entry when today is [p_today].
create or replace function private.earliest_entry_date(p_today date)
returns date
language sql
immutable
set search_path = ''
as $$
  select (p_today - interval '1 year')::date;
$$;

revoke all on function private.earliest_entry_date(date)
  from public, anon, authenticated, service_role;

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
declare
  v_today date;
begin
  if not exists (
    select 1 from public.profiles
    where user_id = p_user and timezone = p_timezone
  ) and not private.is_valid_timezone(p_timezone) then
    raise exception using errcode = '22023', message = 'invalid_timezone';
  end if;
  v_today := private.local_today(p_timezone);
  if p_local_date < private.earliest_entry_date(v_today) then
    raise exception using errcode = '22023', message = 'date_too_old';
  end if;
  if p_local_date > v_today then
    raise exception using errcode = '22023', message = 'date_in_future';
  end if;
end;
$$;

-- Writes ----------------------------------------------------------------------

drop function if exists public.record_metric_entry(
  uuid, numeric, text, date, text, uuid
);

-- Merges one validated entry into its daily aggregate, atomically.
--
-- Result: {"status": "recorded" | "duplicate" | "already_recorded",
--          "aggregate": {...}}
--   recorded          the value was added to the day;
--   duplicate         the same normalised value is already part of this day
--                     (same user, metric and local day) and
--                     p_confirm_duplicate is false: nothing changes, the app
--                     asks whether it is a new measure;
--   already_recorded  this idempotency key was already merged (the client
--                     retried a request that had succeeded): nothing changes.
--
-- With p_confirm_duplicate, an identical value is counted as a new entry
-- (its fingerprint is added once more: one fingerprint per entry). The
-- daily limits and the idempotency key apply as for any entry.
--
-- Concurrency: the day's row is created with INSERT ... ON CONFLICT DO
-- NOTHING, otherwise locked with SELECT ... FOR UPDATE before it is read and
-- updated, so simultaneous entries are applied one after the other and none
-- is lost.
create function public.record_metric_entry(
  p_user_metric_id uuid,
  p_value numeric,
  p_unit text,
  p_local_date date,
  p_timezone text,
  p_idempotency_key uuid,
  p_confirm_duplicate boolean default false
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
      elsif v_fingerprint = any (v_row.entry_fingerprints)
        and not coalesce(p_confirm_duplicate, false) then
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

revoke all on function public.record_metric_entry(
  uuid, numeric, text, date, text, uuid, boolean
) from public, anon, authenticated, service_role;
grant execute on function public.record_metric_entry(
  uuid, numeric, text, date, text, uuid, boolean
) to authenticated;

-- Reads -----------------------------------------------------------------------

-- Points of a chart: one per day, ISO week (Monday) or month. 'auto' keeps
-- every chart under ~120 points: days up to 120 days, weeks up to two years,
-- months beyond. 'day' is refused above 365 calendar days (the app disables
-- it there), 'week' above 7000 days.
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
  if (v_bucket = 'day' and p_to - p_from + 1 > 365)
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

drop function if exists public.get_overview();

-- Data of the "Vue d'ensemble" page: every tracked metric (active or not)
-- with its latest day and the last 30 days compared with the 30 days before.
-- "Today" is p_today, the device's local day sent by the app; it must exist
-- somewhere on Earth right now (between UTC-12 and UTC+14), otherwise
-- 'invalid_today'. Without p_today (calls of Polomix v5), it is today in the
-- profile's time zone, as before. "timezone" is always the profile's zone.
create function public.get_overview(p_today date default null)
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
  if p_today is null then
    v_today := private.local_today(v_timezone);
  elsif p_today < private.local_today('Etc/GMT+12')
    or p_today > private.local_today('Pacific/Kiritimati') then
    raise exception using errcode = '22023', message = 'invalid_today';
  else
    v_today := p_today;
  end if;

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

revoke all on function public.get_overview(date)
  from public, anon, authenticated, service_role;
grant execute on function public.get_overview(date) to authenticated;
