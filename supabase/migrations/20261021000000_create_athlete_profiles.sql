create table if not exists public.athlete_profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  age smallint check (age is null or age between 13 and 120),
  sports text[] not null default '{}',
  weekly_frequency smallint
    check (weekly_frequency is null or weekly_frequency between 0 and 7),
  level text check (
    level is null or level in ('Débutant', 'Intermédiaire', 'Avancé')
  ),
  primary_goal text check (
    primary_goal is null or primary_goal in (
      'Force',
      'Développement musculaire',
      'Endurance',
      'Street workout / calisthenics',
      'Condition physique générale',
      'Reprise progressive'
    )
  ),
  secondary_goals text[] not null default '{}',
  custom_goal text,
  training_locations text[] not null default '{}',
  equipment text[] not null default '{}',
  available_days text[] not null default '{}',
  session_duration_minutes smallint check (
    session_duration_minutes is null
    or session_duration_minutes between 15 and 240
  ),
  limitations text,
  height_cm numeric(5, 1) check (
    height_cm is null or height_cm between 80 and 250
  ),
  weight_kg numeric(5, 1) check (
    weight_kg is null or weight_kg between 25 and 350
  ),
  wearable_source text,
  preferred_palette text not null default 'gold'
    check (preferred_palette in ('gold', 'monochrome', 'blue', 'violet')),
  is_dark_mode boolean not null default true,
  onboarding_step smallint not null default 0
    check (onboarding_step between 0 and 2),
  onboarding_completed boolean not null default false,
  updated_at timestamptz not null default now(),
  constraint completed_profile_has_required_fields check (
    not onboarding_completed
    or (
      age is not null
      and cardinality(sports) > 0
      and weekly_frequency is not null
      and level is not null
      and primary_goal is not null
      and cardinality(training_locations) > 0
    )
  )
);

create or replace function public.set_athlete_profile_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists athlete_profiles_set_updated_at
  on public.athlete_profiles;
create trigger athlete_profiles_set_updated_at
before update on public.athlete_profiles
for each row execute function public.set_athlete_profile_updated_at();

alter table public.athlete_profiles enable row level security;
grant usage on schema public to authenticated;
revoke all on table public.athlete_profiles
  from public, anon, authenticated;
grant select, insert, update on table public.athlete_profiles to authenticated;
revoke all on function public.set_athlete_profile_updated_at()
  from public, anon, authenticated;

drop policy if exists "Users can read their own athlete profile"
  on public.athlete_profiles;
create policy "Users can read their own athlete profile"
on public.athlete_profiles
for select
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "Users can create their own athlete profile"
  on public.athlete_profiles;
create policy "Users can create their own athlete profile"
on public.athlete_profiles
for insert
to authenticated
with check ((select auth.uid()) = user_id);

drop policy if exists "Users can update their own athlete profile"
  on public.athlete_profiles;
create policy "Users can update their own athlete profile"
on public.athlete_profiles
for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);
