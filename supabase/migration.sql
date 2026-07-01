-- ============================================================
-- Seven Store — Supabase Production Migration
-- Run this once in the Supabase SQL Editor (Project → SQL Editor → New query)
-- Safe to re-run: every statement is idempotent (IF NOT EXISTS / guarded).
-- ============================================================

-- ------------------------------------------------------------
-- 1. PRODUCTS TABLE
-- Existing columns assumed: id, product_name, created_at
-- This adds the columns the storefront needs, only if missing.
-- ------------------------------------------------------------

alter table public.products
  add column if not exists price numeric(10,2) not null default 0;

alter table public.products
  add column if not exists description text;

alter table public.products
  add column if not exists image text;

alter table public.products
  add column if not exists active boolean not null default true;

-- Optional metadata used by the product cards/modal (badge, category, etc.)
-- Added defensively so the storefront has richer display data when present,
-- but the site works fine even if you never populate these.
alter table public.products
  add column if not exists category text default 'streaming';

-- The "Other" category has been removed from the storefront entirely.
-- Reassign any existing products that were previously categorized as
-- 'other' to 'streaming' so they remain visible under a real category.
update public.products set category = 'streaming' where category = 'other';

alter table public.products
  add column if not exists badge text;

alter table public.products
  add column if not exists duration text;

alter table public.products
  add column if not exists sort_order integer not null default 0;

alter table public.products
  add column if not exists featured boolean not null default false;

alter table public.products
  add column if not exists updated_at timestamptz not null default now();

-- Keep updated_at current on every update
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_products_updated_at on public.products;
create trigger trg_products_updated_at
  before update on public.products
  for each row
  execute function public.set_updated_at();

-- Index to speed up the storefront's "active products" query
create index if not exists idx_products_active on public.products (active);

-- A unique constraint on product_name lets us safely "upsert" the seed
-- products below (insert if missing, update if already present) without
-- ever creating duplicate rows, no matter how many times this migration
-- is run.
do $$
begin
  if not exists (
    select 1 from information_schema.table_constraints
    where table_name = 'products' and constraint_type = 'UNIQUE' and constraint_name = 'products_product_name_key'
  ) then
    begin
      alter table public.products add constraint products_product_name_key unique (product_name);
    exception when others then
      -- if duplicate product_name rows already exist, this constraint
      -- can't be added until they're de-duplicated by hand; skip rather
      -- than fail the whole migration.
      null;
    end;
  end if;
end $$;

-- ------------------------------------------------------------
-- 2. ORDERS TABLE
-- Created fresh if it doesn't exist; columns added defensively if it does.
-- ------------------------------------------------------------

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  order_number text unique not null,
  customer_name text not null,
  mobile_number text not null,
  email text,
  notes text,
  items jsonb not null default '[]'::jsonb,
  total_price numeric(10,2) not null default 0,
  payment_method text not null,
  status text not null default 'pending',
  created_at timestamptz not null default now()
);

-- Add columns defensively in case the table already existed with a different shape
alter table public.orders add column if not exists order_number text;
alter table public.orders add column if not exists customer_name text;
alter table public.orders add column if not exists mobile_number text;
alter table public.orders add column if not exists email text;
alter table public.orders add column if not exists notes text;
alter table public.orders add column if not exists items jsonb not null default '[]'::jsonb;
alter table public.orders add column if not exists total_price numeric(10,2) not null default 0;
alter table public.orders add column if not exists payment_method text;
alter table public.orders add column if not exists status text not null default 'pending';
alter table public.orders add column if not exists created_at timestamptz not null default now();
alter table public.orders add column if not exists receipt_url text;

-- Ensure order_number is unique and not null once populated for existing rows
do $$
begin
  if not exists (
    select 1 from information_schema.table_constraints
    where table_name = 'orders' and constraint_type = 'UNIQUE' and constraint_name = 'orders_order_number_key'
  ) then
    begin
      alter table public.orders add constraint orders_order_number_key unique (order_number);
    exception when others then
      -- constraint may already exist under a different name, or duplicate data
      -- prevents it; skip rather than fail the whole migration.
      null;
    end;
  end if;
end $$;

create index if not exists idx_orders_status on public.orders (status);
create index if not exists idx_orders_created_at on public.orders (created_at desc);

-- ------------------------------------------------------------
-- 3. ROW LEVEL SECURITY
-- IMPORTANT — read this before going live:
--
-- This project uses Supabase's PUBLISHABLE (anon) key in the browser, which
-- is the correct, intended way to use Supabase from client-side code — but
-- it means anyone can call the same API the website calls. RLS policies are
-- what actually decide what that key is allowed to do. The policies below
-- give the minimum access the storefront needs:
--   • Anyone (anon) can READ active products.
--   • Anyone (anon) can INSERT a new order (placing an order).
--   • Nobody (anon) can READ, UPDATE, or DELETE orders — that is reserved
--     for an authenticated admin (see Admin Panel note below).
-- ------------------------------------------------------------

alter table public.products enable row level security;
alter table public.orders enable row level security;

drop policy if exists "Public can read active products" on public.products;
create policy "Public can read active products"
  on public.products
  for select
  to anon
  using (active = true);

drop policy if exists "Public can insert orders" on public.orders;
create policy "Public can insert orders"
  on public.orders
  for insert
  to anon
  with check (true);

-- No SELECT/UPDATE/DELETE policy is created for anon on orders, so by default
-- those operations are denied for the public key. The admin panel (admin.html)
-- is protected with Supabase Auth (email/password sign-in) and relies on the
-- following policies, scoped to the `authenticated` role only:

drop policy if exists "Authenticated can read all orders" on public.orders;
create policy "Authenticated can read all orders"
  on public.orders
  for select
  to authenticated
  using (true);

drop policy if exists "Authenticated can update orders" on public.orders;
create policy "Authenticated can update orders"
  on public.orders
  for update
  to authenticated
  using (true);

-- ------------------------------------------------------------
-- 3b. STORAGE — payment receipt uploads
-- Bank Transfer and Barq both require the customer to upload a receipt
-- image before the order can be submitted. Files are uploaded straight
-- from the browser (anon key) into a public "receipts" bucket, and the
-- resulting public URL is saved on the order row as `receipt_url`.
-- Public here only means "files can be viewed via their URL if you have
-- it" — the bucket is not listable/browsable by anon, and nobody can
-- overwrite or delete another customer's file.
-- ------------------------------------------------------------

insert into storage.buckets (id, name, public)
values ('receipts', 'receipts', true)
on conflict (id) do nothing;

drop policy if exists "Public can upload receipts" on storage.objects;
create policy "Public can upload receipts"
  on storage.objects
  for insert
  to anon
  with check (bucket_id = 'receipts');

drop policy if exists "Public can view receipts" on storage.objects;
create policy "Public can view receipts"
  on storage.objects
  for select
  to anon
  using (bucket_id = 'receipts');

drop policy if exists "Authenticated can view receipts" on storage.objects;
create policy "Authenticated can view receipts"
  on storage.objects
  for select
  to authenticated
  using (bucket_id = 'receipts');

-- ------------------------------------------------------------
-- 4. CREATING YOUR FIRST ADMIN LOGIN
-- These RLS policies grant order access to ANY authenticated user, so only
-- give the login credentials below to people who should see customer orders.
-- Create an admin login in Supabase → Authentication → Users → Add user
-- (set "Auto Confirm User" so it doesn't need an email confirmation step).
-- Use that email/password to sign in at admin.html.
-- ------------------------------------------------------------

-- ------------------------------------------------------------
-- 5. PRODUCT CATALOG — seed / update with professional descriptions
-- Safe to re-run: matches existing rows by product_name and updates them
-- in place instead of creating duplicates (relies on the unique
-- constraint added above). If a product_name doesn't exist yet, it is
-- inserted. Adjust prices/images any time directly in the Table Editor —
-- re-running this file again will NOT overwrite manual price changes
-- unless you edit the values below first.
--
-- ⚠️ If you have duplicate product_name rows (e.g. two Snapchat rows,
-- two Shahid VIP rows), the unique constraint in Section 1 could not
-- be created, so this ENTIRE insert...on conflict block below will be
-- skipped (you'll see a "Product seed skipped" notice, not an error).
-- Run supabase/dedupe_products.sql FIRST to remove duplicates, then
-- re-run this file to apply the price/description updates.
-- ------------------------------------------------------------

do $$
begin
  insert into public.products (product_name, price, description, image, active, category, duration, sort_order, featured)
  values
    ('MR7 TV', 99, 'اشتراك سنوي — أكثر من 20,000 قناة عربية وعالمية، مكتبة ضخمة من الأفلام والمسلسلات، جودة SD/HD/FHD/4K، تحديث يومي للمحتوى، ضمان كامل طوال مدة الاشتراك.', 'assets/images/image_04.webp', true, 'streaming', '1 Year', 1, true),
    ('Snapchat+', 89, 'اشتراك سنوي — ضمان كامل طوال مدة الاشتراك، تفعيل على حسابك الشخصي، جميع مزايا سناب شات بلس الرسمية، استبدال فوري عند الحاجة، دعم فني متواصل.', 'assets/images/image_05.webp', true, 'social', '1 Year', 2, true),
    ('Shahid VIP', 169.99, 'اشتراك سنوي على حسابك الخاص', 'assets/images/image_06.webp', true, 'streaming', '1 Year', 3, true),
    ('YouTube Premium', 119, 'اشتراك سنوي — مشاهدة بدون إعلانات، تشغيل في الخلفية، تحميل للمشاهدة بدون إنترنت، يشمل يوتيوب ميوزيك بريميوم، يعمل على جميع الأجهزة.', 'assets/images/image_07.webp', true, 'streaming', '1 Year', 4, false),
    ('Disney+', 9.99, 'اشتراك شهري — جودة تصل إلى 4K UHD، دعم HDR و Dolby Vision، يعمل على جميع الأجهزة، إمكانية إنشاء عدة بروفايلات، مكتبة ديزني ومارول وستار وورز الكاملة.', 'assets/images/image_08.webp', true, 'streaming', '1 Month', 5, true),
    ('FASEL+', 19.99, 'اشتراك شهري — أحدث الأفلام والمسلسلات أولاً بأول، جودة عالية بدون تقطيع، يعمل على جميع الأجهزة، تحديث مستمر للمكتبة.', 'assets/images/image_09.webp', true, 'streaming', '1 Month', 6, false),
    ('OSN+', 39, 'اشتراك كامل الحساب — كامل محتوى OSN+ من أفلام ومسلسلات عربية وعالمية حصرية، جودة عالية، يعمل على جميع الأجهزة.', 'assets/images/image_10.webp', true, 'streaming', 'Full Account', 7, false),
    ('Shasha', 9.99, 'اشتراك شهري — أفلام ومسلسلات عربية مختارة، يعمل على جميع الأجهزة، تجربة مشاهدة سلسة وسهلة.', 'assets/images/image_11.webp', true, 'streaming', '1 Month', 8, false),
    ('Netflix', 39, 'اشتراك شهري — جودة عالية تصل إلى 4K (حسب الباقة)، يعمل على جميع الأجهزة، تحديثات مستمرة للمكتبة، ضمان طوال مدة الاشتراك.', 'assets/images/image_12.webp', true, 'streaming', '1 Month', 9, true),
    ('Prime Video', 9.99, 'حساب خاص لمدة شهر واحد — استمتع بمكتبة برايم فيديو الكاملة من أفلام ومسلسلات حصرية، يعمل على جميع الأجهزة، جودة عالية.', 'assets/images/image_13.webp', true, 'streaming', '1 Month', 10, false)
  on conflict (product_name) do update set
    price = excluded.price,
    description = excluded.description,
    image = excluded.image,
    active = excluded.active,
    category = excluded.category,
    duration = excluded.duration,
    sort_order = excluded.sort_order,
    featured = excluded.featured;
exception when others then
  raise notice 'Product seed skipped: % — most likely the product_name unique constraint above could not be created (duplicate names already exist). Add/edit these products manually in the Table Editor instead.', SQLERRM;
end $$;
