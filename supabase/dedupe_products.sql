-- ============================================================
-- Seven Store — Duplicate Product Cleanup
--
-- ⚠️ RUN THIS FILE *BEFORE* (RE-)RUNNING migration.sql, NOT AFTER.
-- migration.sql's price/description updates (Section 5) rely on a
-- UNIQUE constraint on product_name, and Postgres refuses to create
-- that constraint while duplicate names exist — so until the
-- duplicates below are removed, ALL of the price updates in
-- migration.sql (Disney+, Shasha, OSN+, FASEL+, Shahid VIP, etc.)
-- will silently fail as a whole batch, not just the duplicated ones.
--
-- Correct order:
--   1. Run this file (Step 1 then Step 2 below).
--   2. Re-run migration.sql in full.
-- ============================================================
--
-- WHY THIS IS A SEPARATE, MANUAL STEP:
-- migration.sql's own product seed block only knows the product names
-- it ships with ('Snapchat+', 'Shahid VIP', etc). The Arabic-named
-- duplicates you mentioned (e.g. a second "Snapchat" row, a second
-- "شاهد VIP" row) were most likely added later, directly in the Table
-- Editor — they don't exist in any script, so nothing in this repo
-- knows their exact product_name text or id. Guessing the exact string
-- and running a blind DELETE risks deleting the wrong row, so this
-- script is split into two steps: look, then delete.
-- ============================================================

-- STEP 1 — Run this first and read the results.
-- Look for the Snapchat rows and Shahid VIP rows. You want to end up
-- with exactly ONE of each (keep the one you want customers to see —
-- normally the one with the fuller description / correct category).
select id, product_name, price, category, duration, active, created_at
from public.products
where product_name ilike '%snap%'
   or product_name ilike '%سناب%'
   or product_name ilike '%shahid%'
   or product_name ilike '%شاهد%'
order by product_name, created_at;

-- STEP 2 — Delete the duplicate row(s).
-- Copy the `id` (uuid) of the row(s) you do NOT want to keep from the
-- Step 1 results above, paste them into the list below, then run this
-- statement on its own.
--
-- delete from public.products
-- where id in (
--   'PASTE-DUPLICATE-ROW-ID-1',
--   'PASTE-DUPLICATE-ROW-ID-2'
-- );

-- STEP 3 (optional but recommended) — prevent this from happening again.
-- Once you've confirmed there are no duplicate names left, this makes
-- product_name unique going forward so a second insert with the same
-- name will fail loudly instead of silently creating a duplicate.
-- Uncomment and run only after Step 2 leaves no duplicate names:
--
-- alter table public.products
--   add constraint products_product_name_key unique (product_name);
