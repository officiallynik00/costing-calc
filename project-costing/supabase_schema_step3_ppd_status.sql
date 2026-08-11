-- ============================================================
-- Landing Cost Calculator — Optional Step 3 addition
-- Adds a "status" column to ppds so the Worksheet tab can hold
-- in-progress ("draft") consignments, while "Save PPD" moves a
-- consignment to the Saved PPDs tab ("saved").
--
-- IMPORTANT ON DEFAULT VALUE:
-- The default is 'saved' (not 'draft'). That means every PPD you
-- already have in the database today will show up in the "Saved
-- PPDs" tab immediately after this migration runs, and your
-- Worksheet tab will start empty — ready for new entries. This
-- matches the existing data you've already finished entering.
-- Any brand-new PPD created via "+ Add Pragyapan Patra" (or
-- Import Excel) still starts as a 'draft' in the Worksheet, since
-- the app sets that explicitly when creating one.
--
-- The app also works fine if you skip this migration — it will
-- just retry saves without the status field and everything stays
-- in the Worksheet tab as before (Saved PPDs tab will look empty).
--
-- Run this in: Supabase Dashboard > SQL Editor > New query
-- ============================================================

alter table ppds
  add column status text not null default 'saved'
  check (status in ('draft','saved'));

create index idx_ppds_status on ppds(org_id, status);

-- ============================================================
-- End. Safe to run any time; existing rows become 'saved'
-- automatically via the column default.
-- ============================================================
