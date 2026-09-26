-- =====================================================================
--  TIDSPLAN – databas för Supabase
--  Kör hela filen en gång i Supabase: SQL Editor → New query → klistra in → Run.
--  Filen går att köra igen utan att något förstörs.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Vilka som får använda tidsplanen (e-postadresser, små bokstäver)
--    Ändra/lägg till adresser längst ner i filen.
-- ---------------------------------------------------------------------
create table if not exists public.allowed_emails (
  email text primary key check (email = lower(email))
);

-- ---------------------------------------------------------------------
-- 2. Planer (en rad per tidsplan)
-- ---------------------------------------------------------------------
create table if not exists public.plans (
  id            uuid primary key default gen_random_uuid(),
  title         text not null default 'Ny tidsplan',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  updated_email text
);

-- ---------------------------------------------------------------------
-- 3. Moment och projekt (en rad per moment/projekt i en plan)
-- ---------------------------------------------------------------------
create table if not exists public.items (
  id            text primary key,
  plan_id       uuid not null references public.plans(id) on delete cascade,
  kind          text not null default 'task' check (kind in ('task','project')),
  parent        text,                       -- id för projektet ett undermoment tillhör
  name          text not null default '',
  color         text not null default 'Blå',
  hours         numeric not null default 0,
  note          text not null default '',
  collapsed     boolean not null default false,
  segs          jsonb not null default '[]'::jsonb,  -- perioder: [{"s":"2026-10-05","e":"2026-10-09"}, ...]
  created       bigint not null default 0,
  updated_at    timestamptz not null default now(),
  updated_email text
);
create index if not exists items_plan_idx on public.items(plan_id);

-- ---------------------------------------------------------------------
-- 4. Hjälpfunktioner
-- ---------------------------------------------------------------------
-- Är den inloggade användarens e-post med i allowed_emails?
create or replace function public.is_member()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.allowed_emails
    where email = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;
revoke all on function public.is_member() from public, anon;
grant execute on function public.is_member() to authenticated;

-- Sätter tid och vem som ändrade raden
create or replace function public.touch_row()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at := now();
  new.updated_email := auth.jwt() ->> 'email';
  return new;
end;
$$;

drop trigger if exists plans_touch on public.plans;
create trigger plans_touch before insert or update on public.plans
  for each row execute function public.touch_row();

drop trigger if exists items_touch on public.items;
create trigger items_touch before insert or update on public.items
  for each row execute function public.touch_row();

-- ---------------------------------------------------------------------
-- 5. Säkerhet (RLS): bara inloggade användare i allowed_emails
-- ---------------------------------------------------------------------
alter table public.allowed_emails enable row level security;   -- inga regler = ingen åtkomst via webben
alter table public.plans          enable row level security;
alter table public.items          enable row level security;

drop policy if exists "Medlemmar hanterar planer" on public.plans;
create policy "Medlemmar hanterar planer" on public.plans
  for all to authenticated
  using (public.is_member()) with check (public.is_member());

drop policy if exists "Medlemmar hanterar moment" on public.items;
create policy "Medlemmar hanterar moment" on public.items
  for all to authenticated
  using (public.is_member()) with check (public.is_member());

revoke all on public.allowed_emails from anon, authenticated;
revoke all on public.plans, public.items from anon;
grant select, insert, update, delete on public.plans, public.items to authenticated;

-- ---------------------------------------------------------------------
-- 6. Realtid – ändringar skickas direkt till alla som har planen öppen
-- ---------------------------------------------------------------------
alter table public.items replica identity full;
alter table public.plans replica identity full;
do $$
begin
  begin
    alter publication supabase_realtime add table public.items;
  exception when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.plans;
  exception when duplicate_object then null;
  end;
end $$;

-- ---------------------------------------------------------------------
-- 7. ANVÄNDARE – ändra till era riktiga e-postadresser (små bokstäver)
-- ---------------------------------------------------------------------
insert into public.allowed_emails (email) values
  ('patrike90@gmail.com')
  -- , ('kollega@foretaget.se')
on conflict do nothing;

-- Kontroll: ska visa era adresser
select * from public.allowed_emails;
