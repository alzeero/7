# Seven Store — Setup Guide

This project is connected to Supabase for products and orders. Follow these
steps once, in order, before the site goes live.

## 1. Run the database migration

1. Open your Supabase project → **SQL Editor** → **New query**.
2. Copy the entire contents of `supabase/migration.sql` and run it.
3. This is safe to run more than once — every statement checks for
   existence first, so re-running it won't duplicate anything or error
   out on a second pass.

This adds `price`, `description`, `image`, `active`, `category`, `badge`,
`duration`, `featured`, `sort_order`, `updated_at` to your existing
`products` table (keeping `id`, `product_name`, `created_at` as they are),
creates/extends the `orders` table with everything checkout needs, sets up
Row Level Security (see below), **and seeds your full product catalog**
(MR7 TV, Snapchat+, Shahid VIP, YouTube Premium, Disney+, FASEL+, OSN+,
Shasha, Netflix, Prime Video) with prices, images, and professional
descriptions already filled in — no manual product entry needed to launch.

## 2. Manage your products

Your catalog is already populated by the migration above. To add more
products later, or edit prices/descriptions/images for existing ones, use
the Supabase Table Editor → `products` table. At minimum, set:
- `product_name`
- `price`
- `description`
- `image` — a public image URL (upload to Supabase Storage and use the
  public URL, or any other publicly reachable image URL)
- `active` — must be `true` for it to show on the website
- `category` — `streaming` or `social` (matches the filter chips
  on the homepage)
- `featured` — set `true` to show a product in the homepage slider

Re-running `supabase/migration.sql` later will update the 10 seeded
products to match whatever is written in that file at the time — if you've
since changed a price or description by hand in the Table Editor and don't
want it overwritten, edit the corresponding line in `migration.sql` first
(or simply don't re-run the seed section).

## 3. Create your admin login

The admin panel (`admin.html`) requires a real Supabase Auth user — there
is no separate admin password stored anywhere in the code.

1. Supabase Dashboard → **Authentication** → **Users** → **Add user**.
2. Enter an email and password, and check **Auto Confirm User** (so it
   doesn't wait on an email confirmation link).
3. Go to `admin.html` on your site and sign in with that email/password.

Anyone you give these credentials to can see all customer orders — share
them only with trusted staff.

## 4. Understanding the security model (Row Level Security)

The website uses Supabase's **publishable (anon) key**, which is meant to
be visible in browser code — that part is normal and safe. What actually
controls access is the RLS policies created by the migration:

| Who | Can do |
|---|---|
| Public visitors (anon key) | Read products where `active = true`; insert new orders |
| Public visitors (anon key) | **Cannot** read, update, or delete any order |
| Signed-in admin (`authenticated`) | Read and update all orders |

This means a customer's browser can place an order but can never see
anyone else's order data, and the admin panel only works after signing in.

## 5. Deploying

This is a static site — no build step, no server required. Upload every
file in this folder (keeping the same folder structure) to:
- GitHub Pages, or
- Any static host (Netlify, Vercel, Cloudflare Pages, plain Apache/Nginx)

The Supabase project URL and publishable key are already set in
`assets/js/supabase-client.js` — no further configuration is needed for
products/orders to work immediately after deployment.

## 6. Connecting real payment gateways later

See **`PAYMENT_INTEGRATION.md`** for exactly where to add API keys for
Apple Pay, Mada/Visa/Mastercard, and Barq. Bank Transfer already works
with no gateway needed.

## File reference

| File | Purpose |
|---|---|
| `index.html` | Homepage — loads products from Supabase, cart, everything else |
| `checkout.html` | Customer details + payment method + order submission |
| `success.html` | Order confirmation page |
| `admin.html` | Order management dashboard (requires Supabase Auth login) |
| `assets/js/supabase-client.js` | All Supabase API calls (products, orders, auth) |
| `assets/js/cart.js` | Shopping cart logic (localStorage-based) |
| `supabase/migration.sql` | Database schema — run once in Supabase SQL Editor |
| `PAYMENT_INTEGRATION.md` | Where to add payment gateway API keys |
