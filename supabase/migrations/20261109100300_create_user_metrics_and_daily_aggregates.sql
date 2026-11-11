-- Metrics tracked by each user and their daily aggregates (SPEC_PROJECT.md
-- §6, §7.4–7.5, §9).
--
-- No individual entry is ever stored: every validated entry is merged at once
-- into the single row of its (tracked metric, local day). Aggregates are
-- written only by public.record_metric_entry and public.correct_metric_day
-- (20261109100400); clients can read and delete their own rows.

create table if not exists public.user_metrics (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  metric_catalog_id integer not null
    references public.metric_catalog (id) on delete restrict,
  -- false: removed from the active list; its history is kept and readable.
  is_active boolean not null default true,
  is_favorite boolean not null default false,
  sort_order integer not null default 0,
  added_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint user_metrics_once_per_user unique (user_id, metric_catalog_id),
  -- Target of the aggregates' composite foreign key.
  constraint user_metrics_id_user_unique unique (id, user_id)
);

create or replace function private.user_metrics_before_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.user_id = old.user_id;
  new.metric_catalog_id = old.metric_catalog_id;
  new.added_at = old.added_at;
  new.updated_at = pg_catalog.now();
  return new;
end;
$$;

revoke all on function private.user_metrics_before_update()
  from public, anon, authenticated, service_role;

drop trigger if exists user_metrics_before_update on public.user_metrics;
create trigger user_metrics_before_update
before update on public.user_metrics
for each row execute function private.user_metrics_before_update();

create table if not exists public.metric_daily_aggregates (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  user_metric_id uuid not null,
  -- Calendar day of the measure where the user was, chosen in the form.
  local_date date not null check (local_date >= date '1900-01-01'),
  -- IANA zone of the device when the day's first entry was recorded.
  timezone_name text not null check (char_length(timezone_name) between 1 and 64),
  -- Running aggregates of the day's entries, in the metric's storage unit.
  sample_count integer not null check (sample_count between 1 and 200),
  value_sum numeric not null,
  value_min numeric not null,
  value_max numeric not null,
  value_last numeric not null,
  -- Duplicate detection: one 64-bit hash per distinct value merged into the
  -- day (never the values themselves). Never readable by clients.
  entry_fingerprints bigint[] not null,
  -- Client idempotency keys of the requests already merged (bounded).
  request_keys uuid[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint daily_aggregate_once_per_day unique (user_metric_id, local_date),
  -- The tracked metric must belong to the same user as the aggregate.
  constraint daily_aggregate_user_metric_owner
    foreign key (user_metric_id, user_id)
    references public.user_metrics (id, user_id) on delete cascade,
  constraint daily_aggregate_consistent check (
    value_min <= value_last
    and value_last <= value_max
    and value_sum >= value_min * sample_count
    and value_sum <= value_max * sample_count
    and cardinality(entry_fingerprints) = sample_count
    and cardinality(request_keys) <= 200
  )
);

create index if not exists metric_daily_aggregates_user_id_idx
  on public.metric_daily_aggregates (user_id, local_date);

-- RLS -----------------------------------------------------------------------

alter table public.user_metrics enable row level security;
alter table public.metric_daily_aggregates enable row level security;

revoke all on table public.user_metrics
  from public, anon, authenticated, service_role;
grant select, delete on table public.user_metrics to authenticated;
grant insert (user_id, metric_catalog_id, is_active, is_favorite, sort_order)
  on table public.user_metrics to authenticated;
grant update (is_active, is_favorite, sort_order)
  on table public.user_metrics to authenticated;

revoke all on table public.metric_daily_aggregates
  from public, anon, authenticated, service_role;
-- Every column except the fingerprints and the idempotency keys. No INSERT or
-- UPDATE privilege: writes go through the validated functions only.
grant select (
  id, user_id, user_metric_id, local_date, timezone_name, sample_count,
  value_sum, value_min, value_max, value_last, created_at, updated_at
) on table public.metric_daily_aggregates to authenticated;
grant delete on table public.metric_daily_aggregates to authenticated;

drop policy if exists "Users can read their tracked metrics"
  on public.user_metrics;
create policy "Users can read their tracked metrics"
on public.user_metrics
for select
to authenticated
using ((select auth.uid()) = user_id);

-- Only an active catalog metric can be added.
drop policy if exists "Users can track active catalog metrics"
  on public.user_metrics;
create policy "Users can track active catalog metrics"
on public.user_metrics
for insert
to authenticated
with check (
  (select auth.uid()) = user_id
  and exists (
    select 1 from public.metric_catalog c
    where c.id = metric_catalog_id and c.is_active
  )
);

-- A metric retired from the catalog cannot be made active again.
drop policy if exists "Users can update their tracked metrics"
  on public.user_metrics;
create policy "Users can update their tracked metrics"
on public.user_metrics
for update
to authenticated
using ((select auth.uid()) = user_id)
with check (
  (select auth.uid()) = user_id
  and (
    not is_active
    or exists (
      select 1 from public.metric_catalog c
      where c.id = metric_catalog_id and c.is_active
    )
  )
);

-- Deleting a tracked metric deletes its whole history (explicit action in
-- the app, distinct from deactivating it).
drop policy if exists "Users can delete their tracked metrics"
  on public.user_metrics;
create policy "Users can delete their tracked metrics"
on public.user_metrics
for delete
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "Users can read their daily aggregates"
  on public.metric_daily_aggregates;
create policy "Users can read their daily aggregates"
on public.metric_daily_aggregates
for select
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "Users can delete their daily aggregates"
  on public.metric_daily_aggregates;
create policy "Users can delete their daily aggregates"
on public.metric_daily_aggregates
for delete
to authenticated
using ((select auth.uid()) = user_id);

-- INSERT and UPDATE on metric_daily_aggregates: no privilege and no policy
-- for clients (denied twice); see the functions of 20261109100400.
