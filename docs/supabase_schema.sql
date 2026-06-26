-- MyTodo Supabase remote sync table.
--
-- The Flutter client must use a publishable/anon key only. Do not embed a
-- Supabase secret key in Android or Windows builds.
--
-- Without Supabase Auth, row-level isolation cannot be made strong from a
-- public client. The app uses sync_space as a user-chosen namespace, so choose
-- a long, unguessable value if this project is reachable by other people.

create table if not exists public.mytodo_events (
  sync_space text not null,
  event_id text primary key,
  device_id text not null,
  seq integer not null,
  timestamp bigint not null,
  type text not null,
  todo_id text not null,
  payload_json jsonb not null,
  inserted_at timestamptz not null default now()
);

create index if not exists mytodo_events_space_order_idx
  on public.mytodo_events (sync_space, timestamp, seq);

-- For a personal prototype without Supabase Auth, you can use permissive anon
-- policies. This exposes rows to anyone with the publishable key and sync_space.
-- Prefer adding Supabase Auth before using this for sensitive data.
alter table public.mytodo_events enable row level security;

create policy "mytodo_events_anon_select"
  on public.mytodo_events
  for select
  to anon
  using (true);

create policy "mytodo_events_anon_insert"
  on public.mytodo_events
  for insert
  to anon
  with check (true);
