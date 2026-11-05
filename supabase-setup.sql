-- Run once in this Supabase project's SQL Editor.
-- This creates only Multiverse Arena objects and is safe to rerun.
begin;

create table if not exists public.arena_state (
  owner_id uuid primary key references auth.users(id) on delete cascade,
  revision bigint not null default 0
);
create table if not exists public.arena_records (
  owner_id uuid not null references auth.users(id) on delete cascade,
  bucket text not null check (bucket in ('fighters', 'battles')),
  id text not null check (length(id) between 1 and 100),
  data jsonb not null check (jsonb_typeof(data) = 'object' and data->>'id' = id),
  primary key (owner_id, bucket, id)
);
create table if not exists public.arena_requests (
  owner_id uuid not null references auth.users(id) on delete cascade,
  request_id uuid not null,
  revision bigint not null,
  primary key (owner_id, request_id)
);

alter table public.arena_state enable row level security;
alter table public.arena_records enable row level security;
alter table public.arena_requests enable row level security;
-- Tables are accessible only through the authenticated, owner-scoped RPCs below.
revoke all on public.arena_state, public.arena_records, public.arena_requests from anon, authenticated;

create or replace function public.arena_read(p_revision bigint default -1)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  current_owner uuid := auth.uid();
  current_revision bigint;
  result jsonb;
begin
  if current_owner is null then raise exception 'Sign in first'; end if;
  insert into public.arena_state(owner_id) values(current_owner) on conflict do nothing;
  -- The shared lock gives the entire snapshot a consistent revision.
  select revision into current_revision from public.arena_state
    where owner_id = current_owner for share;
  if current_revision = p_revision then
    return jsonb_build_object('revision', current_revision, 'unchanged', true);
  end if;
  select jsonb_build_object(
    'revision', current_revision,
    'fighters', coalesce(jsonb_agg(data order by id) filter (where bucket = 'fighters'), '[]'::jsonb),
    'battles', coalesce(jsonb_agg(data order by data->>'date', id) filter (where bucket = 'battles'), '[]'::jsonb)
  ) into result from public.arena_records where owner_id = current_owner;
  return result;
end;
$$;

create or replace function public.arena_apply(
  p_revision bigint, p_request uuid, p_changes jsonb
)
returns bigint
language plpgsql security definer set search_path = ''
as $$
declare
  current_owner uuid := auth.uid();
  current_revision bigint;
  previous_revision bigint;
  change jsonb;
  record_data jsonb;
  record_id text;
  record_bucket text;
  action text;
begin
  if current_owner is null then raise exception 'Sign in first'; end if;
  if p_request is null or jsonb_typeof(p_changes) is distinct from 'array' then
    raise exception 'Invalid change request';
  end if;
  insert into public.arena_state(owner_id) values(current_owner) on conflict do nothing;
  select revision into current_revision from public.arena_state
    where owner_id = current_owner for update;
  select revision into previous_revision from public.arena_requests
    where owner_id = current_owner and request_id = p_request;
  if found then return previous_revision; end if;
  if p_revision is distinct from current_revision then
    raise exception 'ARENA_CONFLICT: Another device changed this archive. Refresh and try again.';
  end if;
  for change in select value from jsonb_array_elements(p_changes) loop
    record_bucket := change->>'bucket';
    action := change->>'action';
    record_data := change->'data';
    record_id := coalesce(record_data->>'id', change->>'id');
    if record_bucket is null or record_bucket not in ('fighters','battles') then
      raise exception 'Invalid record collection';
    end if;
    if action = 'clear' then
      delete from public.arena_records where owner_id = current_owner and bucket = record_bucket;
    elsif action = 'delete' then
      delete from public.arena_records
        where owner_id = current_owner and bucket = record_bucket and id = record_id;
    elsif action in ('add','put') then
      if record_id is null or length(record_id) not between 1 and 100 then
        raise exception 'Invalid record ID';
      end if;
      if record_bucket = 'fighters' then
        if jsonb_typeof(record_data->'name') is distinct from 'string'
          or jsonb_typeof(record_data->'verse') is distinct from 'string'
          or length(trim(record_data->>'name')) not between 1 and 120
          or length(trim(record_data->>'verse')) not between 1 and 120
          or length(coalesce(record_data->>'notes','')) > 5000
          or length(coalesce(record_data->>'image','')) > 3000
          or (coalesce(record_data->>'image','') <> '' and record_data->>'image' not like 'https://%')
        then raise exception 'Invalid combatant'; end if;
      else
        if record_data->>'winner' is null or record_data->>'loser' is null
          or record_data->>'winner' = record_data->>'loser'
          or coalesce(record_data->>'result','') not in ('close','easy')
          or jsonb_typeof(record_data->'date') is distinct from 'string'
          or jsonb_typeof(record_data->'voided') is distinct from 'boolean'
          or length(coalesce(record_data->>'notes','')) > 5000
        then raise exception 'Invalid battle'; end if;
        perform (record_data->>'date')::timestamptz;
      end if;
      if action = 'add' then
        insert into public.arena_records values(current_owner, record_bucket, record_id, record_data);
      else
        insert into public.arena_records values(current_owner, record_bucket, record_id, record_data)
          on conflict (owner_id, bucket, id) do update set data = excluded.data;
      end if;
    else
      raise exception 'Invalid change action';
    end if;
  end loop;
  -- Reject deleted/missing combatants referenced by any battle, including undone results.
  if exists (
    select 1 from public.arena_records b
    where b.owner_id = current_owner and b.bucket = 'battles'
    and (
      not exists (select 1 from public.arena_records f where f.owner_id = current_owner
        and f.bucket = 'fighters' and f.id = b.data->>'winner')
      or not exists (select 1 from public.arena_records f where f.owner_id = current_owner
        and f.bucket = 'fighters' and f.id = b.data->>'loser')
    )
  ) then raise exception 'A battle references a missing combatant'; end if;
  current_revision := current_revision + 1;
  update public.arena_state set revision = current_revision where owner_id = current_owner;
  insert into public.arena_requests values(current_owner, p_request, current_revision);
  return current_revision;
end;
$$;
revoke all on function public.arena_read(bigint) from public, anon;
revoke all on function public.arena_apply(bigint, uuid, jsonb) from public, anon;
grant execute on function public.arena_read(bigint) to authenticated;
grant execute on function public.arena_apply(bigint, uuid, jsonb) to authenticated;
commit;
