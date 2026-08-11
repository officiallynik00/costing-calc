-- ============================================================
-- Landing Cost Calculator — Supabase schema (Step 1)
-- Run this in: Supabase Dashboard > SQL Editor > New query
-- ============================================================

-- ---------- Extensions ----------
create extension if not exists "pgcrypto"; -- for gen_random_uuid()

-- ---------- Helper: auto-update "updated_at" on any row change ----------
create or replace function set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;


-- ============================================================
-- 1. ORGS  (one row per office/firm — e.g. "Sarthak Industry")
-- ============================================================
create table orgs (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create trigger trg_orgs_updated_at
  before update on orgs
  for each row execute function set_updated_at();


-- ============================================================
-- 2. ORG_MEMBERS  (who belongs to which org, and their role)
--    Links Supabase's built-in auth.users to an org.
-- ============================================================
create table org_members (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null references orgs(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade,
  role        text not null default 'staff' check (role in ('owner','staff')),
  created_at  timestamptz not null default now(),
  unique (org_id, user_id)
);

create index idx_org_members_user on org_members(user_id);
create index idx_org_members_org  on org_members(org_id);


-- ============================================================
-- 3. PPDS  (Pragyapan Patra header — one row per PPD)
-- ============================================================
create table ppds (
  id                    uuid primary key default gen_random_uuid(),
  org_id                uuid not null references orgs(id) on delete cascade,

  company               text,
  date                  text,        -- kept as text: BS dates like "2082/04/01" aren't valid SQL dates
  ppd_no                text,
  party                 text,
  branch_name           text,
  transport_name        text,
  insurance_name        text,

  csf                   numeric(14,2) default 0,
  cvf                   numeric(14,2) default 0,
  misc_costs            numeric(14,2) default 0,
  agent_charges         numeric(14,2) default 0,
  labour_charges        numeric(14,2) default 0,
  other_import_charges  numeric(14,2) default 0,

  created_by            uuid references auth.users(id),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create index idx_ppds_org  on ppds(org_id);
create index idx_ppds_date on ppds(org_id, date);

create trigger trg_ppds_updated_at
  before update on ppds
  for each row execute function set_updated_at();


-- ============================================================
-- 4. PPD_PRODUCTS  (line items — one row per product per PPD)
-- ============================================================
create table ppd_products (
  id                uuid primary key default gen_random_uuid(),
  ppd_id            uuid not null references ppds(id) on delete cascade,

  sno               integer,
  product_name      text,
  unit              text,
  qty               numeric(14,3) default 0,
  basic_am          numeric(14,2) default 0,   -- Basic A/m (IC)
  ext_freight       numeric(14,2) default 0,
  int_freight       numeric(14,2) default 0,
  insurance         numeric(14,2) default 0,
  other_costs       numeric(14,2) default 0,
  deductions        numeric(14,2) default 0,
  import_duty       numeric(14,2) default 0,
  excise_duty       numeric(14,2) default 0,
  other_duties      numeric(14,2) default 0,
  exempt            boolean default false,

  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index idx_ppd_products_ppd on ppd_products(ppd_id);

create trigger trg_ppd_products_updated_at
  before update on ppd_products
  for each row execute function set_updated_at();

-- Note: computed fields (Landing Cost, VAT, Batch Code, etc.) are
-- deliberately NOT stored here. They stay calculated client-side via
-- computePpd(), same as today, fed by these raw rows. That way a
-- formula fix never requires a data migration.


-- ============================================================
-- 5. ROW LEVEL SECURITY
--    Rule: a user can only see/edit rows in orgs they belong to.
-- ============================================================
alter table orgs         enable row level security;
alter table org_members  enable row level security;
alter table ppds         enable row level security;
alter table ppd_products enable row level security;

-- Helper view-like check: is auth.uid() a member of a given org?
-- (expressed inline in each policy below via EXISTS)

-- ---- orgs ----
create policy "member can view own org"
  on orgs for select
  using (
    exists (select 1 from org_members m
            where m.org_id = orgs.id and m.user_id = auth.uid())
  );

create policy "owner can update own org"
  on orgs for update
  using (
    exists (select 1 from org_members m
            where m.org_id = orgs.id and m.user_id = auth.uid() and m.role = 'owner')
  );

-- Org creation happens via a server-side/RPC step in Step 3 (so the
-- creator is auto-added as owner in the same transaction) — no public
-- insert policy on orgs for now.

-- ---- org_members ----
create policy "member can view org roster"
  on org_members for select
  using (
    exists (select 1 from org_members m
            where m.org_id = org_members.org_id and m.user_id = auth.uid())
  );

-- ---- ppds ----
create policy "member can view org ppds"
  on ppds for select
  using (
    exists (select 1 from org_members m
            where m.org_id = ppds.org_id and m.user_id = auth.uid())
  );

create policy "member can insert org ppds"
  on ppds for insert
  with check (
    exists (select 1 from org_members m
            where m.org_id = ppds.org_id and m.user_id = auth.uid())
  );

create policy "member can update org ppds"
  on ppds for update
  using (
    exists (select 1 from org_members m
            where m.org_id = ppds.org_id and m.user_id = auth.uid())
  );

create policy "member can delete org ppds"
  on ppds for delete
  using (
    exists (select 1 from org_members m
            where m.org_id = ppds.org_id and m.user_id = auth.uid())
  );

-- ---- ppd_products (scoped via parent ppd's org) ----
create policy "member can view org ppd_products"
  on ppd_products for select
  using (
    exists (select 1 from ppds p
            join org_members m on m.org_id = p.org_id
            where p.id = ppd_products.ppd_id and m.user_id = auth.uid())
  );

create policy "member can insert org ppd_products"
  on ppd_products for insert
  with check (
    exists (select 1 from ppds p
            join org_members m on m.org_id = p.org_id
            where p.id = ppd_products.ppd_id and m.user_id = auth.uid())
  );

create policy "member can update org ppd_products"
  on ppd_products for update
  using (
    exists (select 1 from ppds p
            join org_members m on m.org_id = p.org_id
            where p.id = ppd_products.ppd_id and m.user_id = auth.uid())
  );

create policy "member can delete org ppd_products"
  on ppd_products for delete
  using (
    exists (select 1 from ppds p
            join org_members m on m.org_id = p.org_id
            where p.id = ppd_products.ppd_id and m.user_id = auth.uid())
  );

-- ============================================================
-- End of Step 1. Nothing here touches the HTML app yet —
-- this just gets the database itself live and locked down.
-- ============================================================
