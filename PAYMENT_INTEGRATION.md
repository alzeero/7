# Payment Gateway Integration Guide — Seven Store

This project ships with the **complete checkout, order, and payment-method
selection UI already built**, but with **no live payment gateway connected
yet** — exactly as requested. Customers select a payment method, the order
is saved to Supabase with `status: 'pending'`, and your team follows up
manually (WhatsApp / phone) to collect payment, until you wire in the real
gateways below.

This document tells you **exactly** where to add each gateway's API keys
and code so that no other file needs to change afterward.

---

## How payment method selection currently works

In `checkout.html`, the customer picks one of three options:

```html
<input type="radio" name="payment_method" value="bank_transfer" />
<input type="radio" name="payment_method" value="barq" />
<input type="radio" name="payment_method" value="bank_cards" />  <!-- currently disabled -->
```

`bank_cards` represents Mada, Visa, and Mastercard combined into a single
option (there is no separate `mada` / `visa` / `mastercard` value anymore).
It has a native `disabled` attribute on its `<input>` and shows a
"currently unavailable" popup when clicked — it cannot be selected or
submitted until you remove `disabled` and wire up a gateway below.

Bank Transfer and Barq both require the customer to upload a payment
receipt image before the order can be submitted. The file is uploaded to
the public `receipts` Storage bucket (see `supabase/migration.sql`) and
its public URL is saved on the order as `receipt_url`, visible in
`admin.html`.

Whichever value is selected gets saved as `payment_method` in the `orders`
table. The order is created **immediately** on submit — no payment has
happened yet, it's just recorded as the customer's chosen method.

---

## Where to add each gateway

All changes happen inside the `<script>` block of **`checkout.html`**, in
the `checkout-form` submit handler — search for this comment:

```js
/* ------------------------------------------------------------
   FORM VALIDATION + SUBMISSION
------------------------------------------------------------ */
```

Right now, that handler calls `createOrder(...)` and then redirects to
`success.html`. To connect a real gateway, you'll insert a payment step
**before** `createOrder(...)` is called (charge first, then save the order
as paid — or save as pending, charge, then update the status, depending on
the gateway's flow).

### 1. Apple Pay

Apple Pay uses the **Apple Pay JS API** directly in the browser — no
separate "API key" file needed for the basic flow, but you do need:
- An Apple Developer Merchant ID
- A Payment Processing Certificate, generated through your payment
  processor (Stripe, Checkout.com, Moyasar, etc. all support Apple Pay
  and will give you exact setup steps)

Add the Apple Pay session code where the `payment_method === 'apple_pay'`
branch would go in the submit handler, e.g.:

```js
if (selectedPayment.value === 'apple_pay') {
  const session = new ApplePaySession(3, paymentRequest);
  session.onvalidatemerchant = async (event) => {
    // call YOUR backend here to validate the merchant session
    // (this step requires a server endpoint — Apple Pay validation
    // cannot be done from the browser alone)
  };
  session.onpaymentauthorized = async (event) => {
    // send event.payment.token to your payment processor to charge it
  };
  session.begin();
}
```

**Note:** Apple Pay merchant validation *must* happen server-side (Apple
requires a server-to-server call with your certificate). This project has
no backend server component yet — you'll need a small server function
(e.g. a Supabase Edge Function) to handle that one step.

### 2. Bank Cards (Mada / Visa / Mastercard — single `bank_cards` option)

Most Saudi payment processors (Moyasar, HyperPay, PayTabs, Tap) provide a
JS SDK that renders a secure card form and returns a token. Typical
integration:

```html
<!-- Add the processor's SDK script tag in checkout.html <head> -->
<script src="https://cdn.YOUR-PROCESSOR.com/sdk.js"></script>
```

```js
// Inside the submit handler, in the payment_method === 'mada' / 'visa' / 'mastercard' branches:
const result = await YourProcessorSDK.charge({
  publishableKey: 'pk_live_XXXXXXXXXXXX',   // <-- your processor's public key goes here
  amount: Math.round(cartTotal() * 100),     // amounts are usually in halalas/cents
  currency: 'SAR',
  source: cardToken
});
```

Put the processor's **publishable/public key** directly in `checkout.html`
(public keys are safe in browser code, same as the Supabase publishable
key). Put the **secret key** only in a server environment (e.g. a Supabase
Edge Function) if the processor requires a server-side charge
confirmation step — never in any file under `assets/`.

### 3. Barq

Barq does not have a widely published self-serve JS SDK at the time of
writing. Contact Barq's business/merchant team directly for their
integration documentation — they will provide either:
- A redirect-based checkout link (simplest: redirect to their hosted page,
  then redirect back to `success.html` on completion), or
- A JS SDK similar to the card processors above.

Once you have their docs, the integration point is the same: the
`payment_method === 'barq'` branch inside the submit handler in
`checkout.html`.

### 4. Bank Transfer

This one needs no gateway at all — it's already fully functional as
shipped. The order is saved with `payment_method: 'bank_transfer'` and
your team shares bank details with the customer manually (e.g. via
WhatsApp) and marks the order `confirmed`/`completed` in the admin panel
once the transfer is verified.

---

## One step you must not forget

Each of the four disabled methods has `disabled` on its `<input>` in
`checkout.html`, plus a `data-disabled="true"` attribute on its parent
`<label>` that triggers the "currently unavailable" popup. Once a gateway
is fully working end-to-end, remove **both** of those from that method's
markup in `checkout.html`, or customers still won't be able to select it.

## Suggested order of integration

1. **Bank Transfer** — already done, no work needed.
2. **Mada/Visa/Mastercard** — easiest to add next; most Saudi processors
   have a pure client-side JS flow with no backend requirement.
3. **Barq** — depends entirely on what their team provides.
4. **Apple Pay** — needs a small server component (Supabase Edge Function)
   for merchant validation; do this last since it's the most involved.

## A note on order status after a real gateway is connected

Once a gateway is live, change this part of the submit handler:

```js
status: 'pending'   // inside createOrder() call — see supabase-client.js
```

to reflect the real outcome — e.g. set it to `'confirmed'` only after the
charge succeeds, or leave it `'pending'` and have your gateway's webhook
(if it has one) call back to update the order status automatically. The
admin panel (`admin.html`) already supports changing any order's status
manually in the meantime.
