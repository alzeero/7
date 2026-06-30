/* ============================================================
   Seven Store — Shopping Cart
   Persisted in localStorage under CART_STORAGE_KEY so it survives
   closing the browser. Shared by index.html and checkout.html.
============================================================ */

const CART_STORAGE_KEY = 'sevenstore_cart_v1';

function cartLoad() {
  try {
    const raw = localStorage.getItem(CART_STORAGE_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch (err) {
    console.error('Cart load error:', err);
    return [];
  }
}

function cartSave(cart) {
  try {
    localStorage.setItem(CART_STORAGE_KEY, JSON.stringify(cart));
  } catch (err) {
    console.error('Cart save error:', err);
  }
}

/* Add a product to the cart (or increment qty if it's already in there).
   `product` should have at least: id, product_name, price, image */
function cartAdd(product, qty = 1) {
  const cart = cartLoad();
  const existing = cart.find(item => String(item.id) === String(product.id));
  if (existing) {
    existing.qty += qty;
  } else {
    cart.push({
      id: product.id,
      product_name: product.product_name,
      price: product.price,
      image: product.image,
      qty: qty
    });
  }
  cartSave(cart);
  cartUpdateBadge();
  return cart;
}

function cartRemove(productId) {
  let cart = cartLoad();
  cart = cart.filter(item => String(item.id) !== String(productId));
  cartSave(cart);
  cartUpdateBadge();
  return cart;
}

function cartIncrement(productId) {
  const cart = cartLoad();
  const item = cart.find(i => String(i.id) === String(productId));
  if (item) item.qty += 1;
  cartSave(cart);
  cartUpdateBadge();
  return cart;
}

function cartDecrement(productId) {
  let cart = cartLoad();
  const item = cart.find(i => String(i.id) === String(productId));
  if (item) {
    item.qty -= 1;
    if (item.qty <= 0) {
      cart = cart.filter(i => String(i.id) !== String(productId));
    }
  }
  cartSave(cart);
  cartUpdateBadge();
  return cart;
}

function cartClear() {
  cartSave([]);
  cartUpdateBadge();
}

function cartCount() {
  return cartLoad().reduce((sum, item) => sum + item.qty, 0);
}

function cartTotal() {
  return cartLoad().reduce((sum, item) => sum + (item.price * item.qty), 0);
}

/* Update every cart-count badge on the current page (header icon, etc.) */
function cartUpdateBadge() {
  const count = cartCount();
  document.querySelectorAll('[data-cart-count]').forEach(el => {
    el.textContent = count > 99 ? '99+' : String(count);
    el.style.display = count > 0 ? 'flex' : 'none';
  });
}

/* Modern toast notification, e.g. "✅ Product added to cart successfully." */
function showToast(message, duration = 2600) {
  let container = document.getElementById('toast-container');
  if (!container) {
    container = document.createElement('div');
    container.id = 'toast-container';
    container.setAttribute('role', 'status');
    container.setAttribute('aria-live', 'polite');
    container.style.cssText = `
      position:fixed; bottom:28px; left:50%; transform:translateX(-50%);
      z-index:10000; display:flex; flex-direction:column; gap:10px;
      align-items:center; pointer-events:none; width:100%; max-width:420px;
      padding:0 16px;
    `;
    document.body.appendChild(container);
  }

  const toast = document.createElement('div');
  toast.textContent = message;
  toast.style.cssText = `
    background:var(--text-900,#0f172a); color:#fff;
    padding:14px 22px; border-radius:14px;
    font-size:.95rem; font-weight:600; text-align:center;
    box-shadow:0 12px 32px rgba(0,0,0,.25);
    opacity:0; transform:translateY(16px);
    transition:opacity .35s ease, transform .35s ease;
    max-width:100%;
  `;
  container.appendChild(toast);

  requestAnimationFrame(() => {
    toast.style.opacity = '1';
    toast.style.transform = 'translateY(0)';
  });

  setTimeout(() => {
    toast.style.opacity = '0';
    toast.style.transform = 'translateY(16px)';
    setTimeout(() => toast.remove(), 350);
  }, duration);
}

/* Run on every page load so the badge reflects localStorage immediately */
document.addEventListener('DOMContentLoaded', cartUpdateBadge);
