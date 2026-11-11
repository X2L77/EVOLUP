-- Minimal stand-in for what a Supabase project provides, so that
-- supabase/migrations can run on a plain local PostgreSQL 17 for the tests.
-- NEVER apply this file to a Supabase project.
--
-- Reproduced: the API roles, auth.users, auth.uid() (reads the JWT claims set
-- by PostgREST in request.jwt.claims), and Supabase's default privileges,
-- which grant everything in schema public to anon, authenticated and
-- service_role (the migrations must revoke them explicitly).

create role anon nologin noinherit;
create role authenticated nologin noinherit;
create role service_role nologin noinherit bypassrls;

create schema auth;
grant usage on schema auth to anon, authenticated, service_role;

create table auth.users (
  id uuid primary key,
  email text
);

create function auth.uid()
returns uuid
language sql
stable
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'
  )::uuid;
$$;
grant execute on function auth.uid() to anon, authenticated, service_role;

grant usage on schema public to anon, authenticated, service_role;
alter default privileges in schema public
  grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public
  grant all on functions to anon, authenticated, service_role;
alter default privileges in schema public
  grant all on sequences to anon, authenticated, service_role;
