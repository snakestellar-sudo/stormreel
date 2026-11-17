-- StormReel database schema for Supabase
-- Paste this whole file into Supabase -> SQL Editor -> New query -> Run.
-- Safe to run more than once.
--
-- Privacy model
--   profiles .......... usernames are public (needed for sign-up checks and adding friends)
--   ratings, reviews,
--   history ........... you, plus anyone YOU have added as a friend
--   watchlist,
--   collections ....... only you
--   friends ........... you see who you added and who added you

-- ---------- tables ----------
create table if not exists public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  username   text not null unique check (username ~ '^[a-z0-9_]{3,20}$'),
  theme      text not null default 'thunderhead',
  created_at timestamptz not null default now()
);

create table if not exists public.ratings (
  user_id    uuid not null references auth.users(id) on delete cascade,
  title_id   text not null,
  stars      smallint not null check (stars between 1 and 5),
  title      jsonb not null default '{}'::jsonb,   -- small snapshot: title, year, poster, type
  updated_at timestamptz not null default now(),
  primary key (user_id, title_id)
);

create table if not exists public.reviews (
  user_id    uuid not null references auth.users(id) on delete cascade,
  title_id   text not null,
  body       text not null check (char_length(body) between 1 and 5000),
  title      jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (user_id, title_id)
);

create table if not exists public.watchlist (
  user_id    uuid not null references auth.users(id) on delete cascade,
  title_id   text not null,
  title      jsonb not null default '{}'::jsonb,
  added_at   timestamptz not null default now(),
  primary key (user_id, title_id)
);

create table if not exists public.history (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  title_id   text not null,
  title      jsonb not null default '{}'::jsonb,
  watched_at timestamptz not null default now()
);
create index if not exists history_user_idx on public.history (user_id, watched_at desc);

create table if not exists public.collections (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  name       text not null check (char_length(name) between 1 and 80),
  created_at timestamptz not null default now(),
  unique (user_id, name)
);

create table if not exists public.collection_items (
  collection_id uuid not null references public.collections(id) on delete cascade,
  title_id      text not null,
  title         jsonb not null default '{}'::jsonb,
  added_at      timestamptz not null default now(),
  primary key (collection_id, title_id)
);

create table if not exists public.friends (
  user_id    uuid not null references auth.users(id) on delete cascade,  -- the person who added
  friend_id  uuid not null references auth.users(id) on delete cascade,  -- the person they added
  created_at timestamptz not null default now(),
  primary key (user_id, friend_id),
  check (user_id <> friend_id)
);
create index if not exists friends_friend_idx on public.friends (friend_id);

-- ---------- create a profile automatically at sign-up ----------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
  insert into public.profiles (id, username)
  values (new.id, lower(new.raw_user_meta_data ->> 'username'));
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- let a signed-in user delete their own account ----------
create or replace function public.delete_me()
returns void
language sql
security definer set search_path = ''
as $$
  delete from auth.users where id = auth.uid();
$$;
revoke all on function public.delete_me() from public, anon;
grant execute on function public.delete_me() to authenticated;

-- ---------- grants (Postgres checks these before row-level security) ----------
grant select on public.profiles to anon, authenticated;
grant update (theme) on public.profiles to authenticated;
grant select, insert, update, delete on
  public.ratings, public.reviews, public.watchlist, public.history,
  public.collections, public.collection_items, public.friends
  to authenticated;

-- ---------- row-level security ----------
alter table public.profiles         enable row level security;
alter table public.ratings          enable row level security;
alter table public.reviews          enable row level security;
alter table public.watchlist        enable row level security;
alter table public.history          enable row level security;
alter table public.collections      enable row level security;
alter table public.collection_items enable row level security;
alter table public.friends          enable row level security;

-- profiles
drop policy if exists "profiles readable" on public.profiles;
create policy "profiles readable" on public.profiles for select to anon, authenticated using (true);
drop policy if exists "own profile update" on public.profiles;
create policy "own profile update" on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- ratings / reviews / history: owner writes; owner + people the owner added can read
do $$
declare t text;
begin
  foreach t in array array['ratings', 'reviews', 'history'] loop
    execute format('drop policy if exists "read own or friend" on public.%I', t);
    execute format($p$
      create policy "read own or friend" on public.%I for select to authenticated using (
        user_id = (select auth.uid())
        or exists (select 1 from public.friends f
                   where f.user_id = %I.user_id and f.friend_id = (select auth.uid()))
      )$p$, t, t);
    execute format('drop policy if exists "write own" on public.%I', t);
    execute format($p$
      create policy "write own" on public.%I for all to authenticated
        using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()))
      $p$, t);
  end loop;
end $$;

-- watchlist / collections: private
drop policy if exists "own watchlist" on public.watchlist;
create policy "own watchlist" on public.watchlist for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

drop policy if exists "own collections" on public.collections;
create policy "own collections" on public.collections for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

drop policy if exists "own collection items" on public.collection_items;
create policy "own collection items" on public.collection_items for all to authenticated
  using (exists (select 1 from public.collections c where c.id = collection_id and c.user_id = (select auth.uid())))
  with check (exists (select 1 from public.collections c where c.id = collection_id and c.user_id = (select auth.uid())));

-- friends
drop policy if exists "see my friend links" on public.friends;
create policy "see my friend links" on public.friends for select to authenticated
  using (user_id = (select auth.uid()) or friend_id = (select auth.uid()));
drop policy if exists "add friend" on public.friends;
create policy "add friend" on public.friends for insert to authenticated
  with check (user_id = (select auth.uid()));
drop policy if exists "remove friend" on public.friends;
create policy "remove friend" on public.friends for delete to authenticated
  using (user_id = (select auth.uid()));
