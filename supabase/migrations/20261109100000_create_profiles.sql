-- EVOLUP V1 user profile (SPEC_PROJECT.md §7.1): display name, IANA time
-- zone, appearance and privacy preferences. One row per user, created by the
-- app at the first sign-in after this migration.
--
-- public.athlete_profiles (sports questionnaire of the previous vision) is
-- neither modified nor dropped: its rows stay in the database, the app simply
-- no longer reads it.

-- Internal helpers live in a schema that the Data API does not expose
-- (supabase/config.toml: api.schemas = public, graphql_public).
create schema if not exists private;
revoke all on schema private from public, anon, authenticated, service_role;
grant usage on schema private to authenticated;

-- An IANA time zone known to this PostgreSQL server (e.g. 'Europe/Paris').
-- POSIX strings such as 'UTC+3' are rejected on purpose.
create or replace function private.is_valid_timezone(p_name text)
returns boolean
language sql
stable
set search_path = ''
as $$
  select p_name is not null
    and char_length(p_name) between 1 and 64
    and exists (
      select 1 from pg_catalog.pg_timezone_names where name = p_name
    );
$$;

revoke all on function private.is_valid_timezone(text)
  from public, anon, authenticated, service_role;
grant execute on function private.is_valid_timezone(text) to authenticated;

create table if not exists public.profiles (
  user_id uuid primary key default auth.uid()
    references auth.users (id) on delete cascade,
  display_name text check (
    display_name is null
    or (
      char_length(display_name) between 1 and 60
      and display_name = btrim(display_name)
    )
  ),
  timezone text not null default 'UTC',
  theme_palette text not null default 'blue' check (
    theme_palette in ('gold', 'black_white', 'blue', 'violet')
  ),
  theme_mode text not null default 'dark' check (
    theme_mode in ('dark', 'light')
  ),
  -- Polomix may read the user's tracked data only after an explicit opt-in.
  coach_data_access boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function private.profiles_before_write()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' or new.timezone is distinct from old.timezone then
    if not private.is_valid_timezone(new.timezone) then
      raise exception using errcode = '22023', message = 'invalid_timezone';
    end if;
  end if;
  if tg_op = 'UPDATE' then
    new.created_at = old.created_at;
  end if;
  new.updated_at = pg_catalog.now();
  return new;
end;
$$;

revoke all on function private.profiles_before_write()
  from public, anon, authenticated, service_role;

drop trigger if exists profiles_before_write on public.profiles;
create trigger profiles_before_write
before insert or update on public.profiles
for each row execute function private.profiles_before_write();

alter table public.profiles enable row level security;
revoke all on table public.profiles
  from public, anon, authenticated, service_role;
grant select on table public.profiles to authenticated;
grant insert (
  user_id, display_name, timezone, theme_palette, theme_mode,
  coach_data_access
) on table public.profiles to authenticated;
grant update (
  display_name, timezone, theme_palette, theme_mode, coach_data_access
) on table public.profiles to authenticated;

drop policy if exists "Users can read their own profile" on public.profiles;
create policy "Users can read their own profile"
on public.profiles
for select
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "Users can create their own profile" on public.profiles;
create policy "Users can create their own profile"
on public.profiles
for insert
to authenticated
with check ((select auth.uid()) = user_id);

drop policy if exists "Users can update their own profile" on public.profiles;
create policy "Users can update their own profile"
on public.profiles
for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

-- Time zones offered by the settings screen (IANA region/city names).
create or replace function public.list_timezones()
returns setof text
language sql
stable
set search_path = ''
as $$
  select name
  from pg_catalog.pg_timezone_names
  where name = 'UTC'
    or (
      name ~ '^(Africa|America|Antarctica|Asia|Atlantic|Australia|Europe|Indian|Pacific)/'
      and name !~ '^(posix|right)/'
    )
  order by name;
$$;

revoke all on function public.list_timezones()
  from public, anon, authenticated, service_role;
grant execute on function public.list_timezones() to authenticated;
