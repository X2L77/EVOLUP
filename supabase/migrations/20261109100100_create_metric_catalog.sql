-- EVOLUP metric catalog (SPEC_PROJECT.md §4 and §7.2–7.3): categories and
-- predefined metrics shared by every user. Reference data owned by EVOLUP:
-- signed-in users can read it, nobody can write it through the Data API.
-- Rows are added by migrations only (see 20261109100200_seed_metric_catalog
-- for the pattern). Identifiers are explicit and permanent.

create table if not exists public.metric_categories (
  id smallint primary key,
  slug text not null unique check (slug ~ '^[a-z][a-z0-9_]{1,47}$'),
  name text not null check (char_length(name) between 1 and 60),
  description text not null default '' check (char_length(description) <= 300),
  sort_order smallint not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

-- Values are always stored in the metric's storage unit:
--   repetition, page, task: whole counts;
--   meter: distances;
--   second: durations (whole seconds);
--   point: scores between min_value and max_value.
-- The app shows `stored / display_factor` with `display_decimals` decimals
-- and `unit_label` (durations are shown as hours/minutes/seconds instead).
create table if not exists public.metric_catalog (
  id integer primary key,
  slug text not null unique check (slug ~ '^[a-z][a-z0-9_]{1,63}$'),
  category_id smallint not null references public.metric_categories (id),
  name text not null check (char_length(name) between 1 and 80),
  description text not null check (char_length(description) between 1 and 500),
  value_kind text not null check (
    value_kind in ('integer', 'decimal', 'duration', 'score')
  ),
  storage_unit text not null check (
    storage_unit in ('repetition', 'page', 'task', 'meter', 'second', 'point')
  ),
  -- Decimals allowed in the storage unit (0 = whole numbers only).
  storage_scale smallint not null default 0 check (storage_scale between 0 and 4),
  unit_label text not null check (char_length(unit_label) between 1 and 20),
  display_factor numeric not null default 1 check (display_factor > 0),
  display_decimals smallint not null default 0 check (
    display_decimals between 0 and 4
  ),
  -- How several entries of the same local day are combined.
  aggregation text not null check (
    aggregation in ('average', 'sum', 'max', 'min', 'last')
  ),
  -- Whether a personal record makes sense, and which direction is better.
  -- NULL: no record is computed for this metric.
  record_direction text check (record_direction in ('higher', 'lower')),
  min_value numeric,
  max_value numeric,
  -- Upper bound of a day's total, for metrics aggregated by sum.
  daily_sum_max numeric,
  -- Form options read by the app, e.g. {"duration_fields": ["hours",
  -- "minutes"]}. Unknown keys are ignored by the app.
  form_config jsonb not null default '{}'::jsonb check (
    jsonb_typeof(form_config) = 'object'
  ),
  -- Lowercase words without accents used to recognise the metric in a
  -- Polomix message and in the app's search.
  keywords text[] not null default '{}',
  is_active boolean not null default true,
  sort_order smallint not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint metric_bounds_ordered check (
    min_value is null or max_value is null or min_value <= max_value
  ),
  constraint metric_daily_sum_only_for_sum check (
    daily_sum_max is null
    or (aggregation = 'sum' and (max_value is null or daily_sum_max >= max_value))
  ),
  constraint metric_whole_numbers check (
    value_kind not in ('integer', 'duration') or storage_scale = 0
  ),
  constraint metric_duration_in_seconds check (
    (value_kind = 'duration') = (storage_unit = 'second')
  ),
  constraint metric_score_bounded check (
    value_kind <> 'score' or (min_value is not null and max_value is not null)
  )
);

create index if not exists metric_catalog_category_id_idx
  on public.metric_catalog (category_id);

-- Stable definitions: a metric's identity and storage semantics cannot change
-- once users track it (create a new metric and retire the old one instead).
-- The foreign key from user_metrics already prevents deleting such a metric.
create or replace function private.metric_catalog_before_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.id <> old.id or new.slug <> old.slug then
    raise exception using
      errcode = '55000',
      message = 'metric_identity_is_permanent';
  end if;
  if (
    new.value_kind, new.storage_unit, new.storage_scale, new.aggregation
  ) is distinct from (
    old.value_kind, old.storage_unit, old.storage_scale, old.aggregation
  ) and exists (
    select 1 from public.user_metrics where metric_catalog_id = old.id
  ) then
    raise exception using
      errcode = '55000',
      message = 'metric_storage_is_permanent_once_tracked';
  end if;
  new.created_at = old.created_at;
  new.updated_at = pg_catalog.now();
  return new;
end;
$$;

revoke all on function private.metric_catalog_before_update()
  from public, anon, authenticated, service_role;

drop trigger if exists metric_catalog_before_update on public.metric_catalog;
create trigger metric_catalog_before_update
before update on public.metric_catalog
for each row execute function private.metric_catalog_before_update();

alter table public.metric_categories enable row level security;
alter table public.metric_catalog enable row level security;
revoke all on table public.metric_categories
  from public, anon, authenticated, service_role;
revoke all on table public.metric_catalog
  from public, anon, authenticated, service_role;
grant select on table public.metric_categories to authenticated;
grant select on table public.metric_catalog to authenticated;

drop policy if exists "Signed-in users can read metric categories"
  on public.metric_categories;
create policy "Signed-in users can read metric categories"
on public.metric_categories
for select
to authenticated
using (true);

-- Retired metrics stay readable so that their history can be displayed; the
-- app only offers active metrics for tracking, and the database refuses to
-- track a retired one (user_metrics policies). The policy does not look at
-- user_metrics, whose policies read this table (no policy recursion).
drop policy if exists "Signed-in users can read the metric catalog"
  on public.metric_catalog;
create policy "Signed-in users can read the metric catalog"
on public.metric_catalog
for select
to authenticated
using (true);
