-- Initial questionnaire answers (SPEC_PROJECT.md §2): one row per user,
-- created only when the questionnaire is finished. Allowed values mirror
-- lib/data/profile_rules.dart; test/profile_rules_test.dart checks both stay
-- identical.
create table if not exists public.athlete_profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  age smallint not null check (age between 15 and 120),
  height_cm numeric(4, 1) not null check (height_cm between 80 and 250),
  weight_kg numeric(4, 1) not null check (weight_kg between 25 and 350),
  weekly_sessions smallint not null check (weekly_sessions between 2 and 7),
  training_days text[] not null check (
    training_days <@ array[
      'Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'
    ]::text[]
  ),
  level text not null check (
    level in ('Débutant', 'Intermédiaire', 'Avancé')
  ),
  primary_goal text not null check (
    primary_goal in (
      'Force',
      'Développement musculaire',
      'Endurance',
      'Street workout / calisthenics',
      'Condition physique générale',
      'Reprise progressive'
    )
  ),
  goal_details text check (
    goal_details is null or char_length(goal_details) between 1 and 200
  ),
  training_locations text[] not null check (
    cardinality(training_locations) >= 1
    and training_locations <@ array[
      'À domicile', 'Salle de sport', 'Street workout'
    ]::text[]
  ),
  home_equipment text[] not null default '{}' check (
    home_equipment <@ array[
      'Aucun matériel',
      'Haltères',
      'Barre et poids',
      'Élastiques',
      'Kettlebell',
      'Banc',
      'Machines',
      'Barre de traction',
      'Autre'
    ]::text[]
    and not (
      'Aucun matériel' = any (home_equipment)
      and cardinality(home_equipment) > 1
    )
  ),
  session_duration_minutes smallint not null check (
    session_duration_minutes in (30, 45, 60, 75, 90)
  ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Each selected day holds one session; the other days are rest days.
  constraint one_training_day_per_session check (
    cardinality(training_days) = weekly_sessions
  ),
  -- A day can only be selected once.
  constraint training_days_unique check (
    cardinality(array_positions(training_days, 'Lundi')) <= 1
    and cardinality(array_positions(training_days, 'Mardi')) <= 1
    and cardinality(array_positions(training_days, 'Mercredi')) <= 1
    and cardinality(array_positions(training_days, 'Jeudi')) <= 1
    and cardinality(array_positions(training_days, 'Vendredi')) <= 1
    and cardinality(array_positions(training_days, 'Samedi')) <= 1
    and cardinality(array_positions(training_days, 'Dimanche')) <= 1
  ),
  -- Equipment is only asked, and required, when the user trains at home.
  constraint home_equipment_only_at_home check (
    case
      when 'À domicile' = any (training_locations)
        then cardinality(home_equipment) >= 1
      else cardinality(home_equipment) = 0
    end
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
-- service_role bypasses RLS: it gets nothing here (not even the default
-- TRUNCATE); a server-side feature will need its own explicit grant.
revoke all on table public.athlete_profiles
  from public, anon, authenticated, service_role;
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
