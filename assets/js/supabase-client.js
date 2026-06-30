/* ============================================================
   Seven Store — Supabase Client
   Loads the Supabase JS SDK from CDN and exposes small, focused
   helper functions used across the site (storefront + admin).

   IMPORTANT — about the key below:
   This is the PUBLISHABLE (anon) key, which is meant to be used in
   browser code — it is not a secret. What actually controls access
   is Row Level Security (RLS) on each table (see supabase/migration.sql).
   Never put a service_role key in any file under assets/ — that key
   bypasses RLS entirely and must only ever be used in a trusted
   server environment, never shipped to a browser.
============================================================ */

const SUPABASE_URL = 'https://lqrravkonftmmarqcwzn.supabase.co';
const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_b7y81Z0E8XZZIUn2MCtRxA_SswAddYC';

let _supabaseClient = null;
let _supabaseReadyPromise = null;

/* Lazily load the Supabase SDK from CDN once, then create a single
   shared client instance for the rest of the page's lifetime. */
function getSupabaseClient() {
  if (_supabaseReadyPromise) return _supabaseReadyPromise;

  _supabaseReadyPromise = new Promise((resolve, reject) => {
    if (window.supabase && typeof window.supabase.createClient === 'function') {
      _supabaseClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
      resolve(_supabaseClient);
      return;
    }

    const script = document.createElement('script');
    script.src = 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.min.js';
    script.async = true;
    script.onload = () => {
      try {
        _supabaseClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
        resolve(_supabaseClient);
      } catch (err) {
        reject(err);
      }
    };
    script.onerror = () => reject(new Error('Failed to load Supabase SDK from CDN'));
    document.head.appendChild(script);
  });

  return _supabaseReadyPromise;
}

/* ------------------------------------------------------------
   PRODUCTS
------------------------------------------------------------ */

/* Fetch all active products, ordered for display.
   Returns [] on failure (never throws) so the storefront can show
   a graceful empty/error state instead of breaking the page. */
async function fetchActiveProducts() {
  try {
    const client = await getSupabaseClient();
    const { data, error } = await client
      .from('products')
      .select('id, product_name, price, description, image, active, category, badge, duration, featured, sort_order, created_at')
      .eq('active', true)
      .order('sort_order', { ascending: true })
      .order('created_at', { ascending: true });

    if (error) {
      console.error('Supabase fetchActiveProducts error:', error.message);
      return [];
    }
    return data || [];
  } catch (err) {
    console.error('Supabase fetchActiveProducts exception:', err);
    return [];
  }
}

/* ------------------------------------------------------------
   ORDERS
------------------------------------------------------------ */

/* Generate a human-friendly, reasonably-unique order number.
   Format: SS-YYYYMMDD-XXXX (XXXX = random base36 chars). This is
   generated client-side for display purposes; the database row's
   own UUID `id` remains the true unique key. */
function generateOrderNumber() {
  const now = new Date();
  const y = now.getFullYear();
  const m = String(now.getMonth() + 1).padStart(2, '0');
  const d = String(now.getDate()).padStart(2, '0');
  const rand = Math.random().toString(36).slice(2, 6).toUpperCase();
  return `SS-${y}${m}${d}-${rand}`;
}

/* Insert a new order. `items` should be the cart array
   [{ id, product_name, price, qty }, ...].
   Returns { success: true, orderNumber } or { success: false, error }.

   IMPORTANT: this intentionally does NOT chain .select() after .insert().
   Supabase's RLS only grants the public (anon) key INSERT access on
   orders, not SELECT (so customers can never browse each other's
   orders). Asking PostgREST to return the inserted row via .select()
   requires SELECT permission too, so it would fail even though the
   insert itself succeeded — which is exactly the bug that made every
   order silently fail before. The order number is generated up front
   and returned directly instead of being read back from the database. */
async function createOrder({ customerName, mobileNumber, email, notes, items, totalPrice, paymentMethod }) {
  try {
    const client = await getSupabaseClient();
    const orderNumber = generateOrderNumber();

    const { error } = await client
      .from('orders')
      .insert([{
        order_number: orderNumber,
        customer_name: customerName,
        mobile_number: mobileNumber,
        email: email || null,
        notes: notes || null,
        items: items,
        total_price: totalPrice,
        payment_method: paymentMethod,
        status: 'pending'
      }]);

    if (error) {
      console.error('Supabase createOrder error:', error.message);
      return { success: false, error: error.message };
    }

    return { success: true, orderNumber: orderNumber };
  } catch (err) {
    console.error('Supabase createOrder exception:', err);
    return { success: false, error: err.message || 'Unknown error' };
  }
}

/* ------------------------------------------------------------
   ADMIN AUTH
   admin.html uses email/password sign-in via Supabase Auth. Once
   signed in, the same client automatically attaches the user's
   session to every request, so fetchAllOrders()/updateOrderStatus()
   above start working (per the `authenticated`-role RLS policies
   in supabase/migration.sql).
------------------------------------------------------------ */

async function adminSignIn(email, password) {
  try {
    const client = await getSupabaseClient();
    const { data, error } = await client.auth.signInWithPassword({ email, password });
    if (error) {
      return { success: false, error: error.message };
    }
    return { success: true, session: data.session };
  } catch (err) {
    return { success: false, error: err.message };
  }
}

async function adminSignOut() {
  try {
    const client = await getSupabaseClient();
    await client.auth.signOut();
    return { success: true };
  } catch (err) {
    return { success: false, error: err.message };
  }
}

async function adminGetSession() {
  try {
    const client = await getSupabaseClient();
    const { data } = await client.auth.getSession();
    return data.session;
  } catch (err) {
    console.error('adminGetSession error:', err);
    return null;
  }
}

/* ------------------------------------------------------------
   ADMIN — order management
   These rely on the signed-in session above + the `authenticated`
   RLS policies in supabase/migration.sql. They will fail with a
   permissions error if called while signed out, or if those
   policies haven't been applied yet.
------------------------------------------------------------ */

async function fetchAllOrders() {
  try {
    const client = await getSupabaseClient();
    const { data, error } = await client
      .from('orders')
      .select('*')
      .order('created_at', { ascending: false });

    if (error) {
      console.error('Supabase fetchAllOrders error:', error.message);
      return { success: false, error: error.message, orders: [] };
    }
    return { success: true, orders: data || [] };
  } catch (err) {
    console.error('Supabase fetchAllOrders exception:', err);
    return { success: false, error: err.message, orders: [] };
  }
}

async function updateOrderStatus(orderId, newStatus) {
  try {
    const client = await getSupabaseClient();
    const { error } = await client
      .from('orders')
      .update({ status: newStatus })
      .eq('id', orderId);

    if (error) {
      console.error('Supabase updateOrderStatus error:', error.message);
      return { success: false, error: error.message };
    }
    return { success: true };
  } catch (err) {
    console.error('Supabase updateOrderStatus exception:', err);
    return { success: false, error: err.message };
  }
}
