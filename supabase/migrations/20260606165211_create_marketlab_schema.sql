-- MarketLab schema: profiles, markets, positions, ledger_entries

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

-- Workshop fake starting balance: $10,000.00 (1,000,000 cents)
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, first_name, last_name, balance_cents)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'first_name', ''),
    coalesce(new.raw_user_meta_data->>'last_name', ''),
    1000000
  );
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  balance_cents bigint not null default 0 check (balance_cents >= 0),
  first_name text not null default '',
  last_name text not null default '',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table public.markets (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text not null default '',
  status text not null default 'open' check (status in ('open', 'closed', 'resolved')),
  close_date timestamptz not null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table public.positions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  market_id uuid not null references public.markets (id) on delete cascade,
  yes_shares_cents bigint not null default 0 check (yes_shares_cents >= 0),
  no_shares_cents bigint not null default 0 check (no_shares_cents >= 0),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (user_id, market_id)
);

create table public.ledger_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  market_id uuid references public.markets (id) on delete set null,
  amount_cents bigint not null,
  entry_type text not null,
  description text not null default '',
  created_at timestamptz not null default timezone('utc', now())
);

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------

create index positions_user_id_idx on public.positions (user_id);
create index positions_market_id_idx on public.positions (market_id);
create index ledger_entries_user_id_idx on public.ledger_entries (user_id);
create index ledger_entries_market_id_idx on public.ledger_entries (market_id);

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

create trigger markets_set_updated_at
  before update on public.markets
  for each row execute function public.set_updated_at();

create trigger positions_set_updated_at
  before update on public.positions
  for each row execute function public.set_updated_at();

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.markets enable row level security;
alter table public.positions enable row level security;
alter table public.ledger_entries enable row level security;

-- Public market data is readable by everyone.
create policy "Markets are viewable by everyone"
  on public.markets
  for select
  to anon, authenticated
  using (true);

-- Users can read their own profile. No client write policies (balance changes are server-side).
create policy "Users can view their own profile"
  on public.profiles
  for select
  to authenticated
  using ((select auth.uid()) = id);

create policy "Users can view their own positions"
  on public.positions
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "Users can view their own ledger entries"
  on public.ledger_entries
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------------------
-- API grants (RLS controls which rows each role can see)
-- ---------------------------------------------------------------------------

grant usage on schema public to anon, authenticated;

grant select on table public.markets to anon, authenticated;
grant select on table public.profiles to authenticated;
grant select on table public.positions to authenticated;
grant select on table public.ledger_entries to authenticated;
