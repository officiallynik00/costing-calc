-- ============================================================
-- Landing Cost Calculator — Optional Step 2 addition
-- Adds persistence for "saved views" in the Data Analysis tab
-- (named group/filter/value-field presets).
--
-- This is OPTIONAL. If you skip this migration, saved views
-- still work, but only for the current browser session/tab —
-- they won't survive a refresh or be shared with teammates.
--
-- Run this in: Supabase Dashboard > SQL Editor > New query
-- ============================================================

create table saved_views (
  id          uuid primary key default gen_random_uuid(),
  org_id      uuid not null references orgs(id) on delete cascade,
  name        text not null,
  config      jsonb not null,          -- serialized analysisState (level, filters, groupBy, valueFields...)
  created_by  uuid references auth.users(id),
  created_at  timestamptz not null default now()
);

create index idx_saved_views_org on saved_views(org_id);

alter table saved_views enable row level security;

create policy "member can view org saved_views"
  on saved_views for select
  using (
    exists (select 1 from org_members m
            where m.org_id = saved_views.org_id and m.user_id = auth.uid())
  );

create policy "member can insert org saved_views"
  on saved_views for insert
  with check (
    exists (select 1 from org_members m
            where m.org_id = saved_views.org_id and m.user_id = auth.uid())
  );

create policy "member can delete org saved_views"
  on saved_views for delete
  using (
    exists (select 1 from org_members m
            where m.org_id = saved_views.org_id and m.user_id = auth.uid())
  );

-- ============================================================
-- End. The app already degrades gracefully if this table is
-- missing (it falls back to session-only saved views), so this
-- can be run any time — before or after the frontend update.
-- ============================================================
