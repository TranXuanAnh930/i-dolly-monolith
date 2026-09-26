# Use case flows

[← Back to README](../README.md)

Multi-step journeys spanning several endpoints — each request is stateless; every step below is a
separate HTTP call, tied together only by tokens/ids the previous step handed back.

| # | Flow | Actor |
|---|---|---|
| 1 | [Forgot password → reset → log back in](#1-forgot-password--reset-it--log-back-in) | Fan |
| 2 | [Add to cart → checkout → notified](#2-add-to-cart--checkout--notified-on-two-channels) | Fan |
| 3 | [Lottery: rank → apply → draw → pay](#3-lottery-entry--manager-triggered-draw--win--pay--ticket-in-hand) | Fan + manager |
| 4 | [Buy a direct-sale ticket](#4-buy-a-direct-sale-ticket) | Fan |
| 5 | [Set up a concert for sale](#5-set-up-a-concert-for-sale) | Manager |
| 6 | [Ship an order](#6-ship-an-order) | Manager |

### 1. Forgot password → reset it → log back in

1. `POST /profile/forgot-password` — always returns the same generic message whether or not the
   email is registered, so the endpoint can't be used to enumerate accounts. If it is registered,
   `reset_password_process` mints a short-lived JWT reset token (`EMAIL_TOKEN_EXPIRE_MINUTES`) and
   queues an email carrying it through Celery (`celery_app.send_task`), like every other email.
2. The fan follows the link in that email, which opens the frontend's `/reset-password` page (in
   local dev with `DEBUG=true`, the email is printed to the console instead of sent). That page
   calls `POST /profile/set-password` with `{token, new_password}`. This revokes every existing
   refresh token for the account — a session an attacker already held doesn't survive the reset
   meant to lock them out — and writes an in-app `password_reset` notification.
3. `POST /account/login` with the new password — ordinary login, a fresh access/refresh token
   pair.

### 2. Add to cart → checkout → notified on two channels

1. `POST /cart/add_cart` — locks the product row, checks stock, and adds or updates the cart row at
   the product's current price.
2. `POST /order/checkout` (3 requests per 60 s per user) — carries a shipping address, the expected
   total, the gateway and an idempotency key. It checks the resale cap, locks every affected
   `Product` row (fixed id order, deadlock-safe), checks stock under that lock, and creates
   `Order`/`OrderItem`/`Payment` plus the order's shipping-status row in one commit. Only on a
   successful payment does that same commit also decrement stock, clear the cart, and write an
   in-app `order_confirmation` notification; the product-list, store-page and product-detail
   caches are invalidated right after, once the commit lands.
3. Back in the router, once `checkout()` returns without the order having been cancelled outright
   (a declined mock payment cancels it immediately — no confirmation email for that case): an
   `EmailTemplate.ORDER_PLACED` email is dispatched via `celery_app.send_task(...)`, off the
   request/response cycle entirely, picked up whenever the Celery worker gets to it.

With PayPal, the order stays `pending` until the capture or webhook finalizes it (the same
`finalize_paypal_payment` path as tickets in [Architecture](architecture.md#data-flow)); stock is
only decremented then.

### 3. Lottery entry → manager-triggered draw → win → pay → ticket in hand

1. `POST /lottery_preferences/set` — the fan ranks tiers for a concert (1st VIP, 2nd Premium, …).
   Every ranked tier needs a lottery campaign whose entry window has started, and the ranking can't
   change once entries close.
2. `POST /lottery_entries/apply` (or `/apply-batch` for several tiers at once) — free, no cart, no
   payment; accepted only while the campaign is open and inside its entry window. Rejected if the
   fan already holds a live ticket for that concert or hasn't ranked the tier. Each entry creates a
   `lottery_registered` notification.
3. After every campaign's window has closed, a manager calls `PUT /concerts/lottery-draw/{id}`,
   which only validates RBAC and enqueues `app.tasks.lottery.draw_lottery` — the actual rank-cascade
   draw runs inside the Celery worker, locking every affected `ticket_type`/`lottery_campaign`/
   `lottery_entry` row for that concert before touching any of them. A win inserts a
   `pending_payment` Ticket row and reserves the seat (`ticket_types.sold_quantity += 1`)
   immediately, before any money moves; a loss writes nothing to inventory at all. (Which
   notifications fire around this step, and why win/loss email was cut — see
   [Engineering decisions](engineering-decisions.md#lottery-notifications).)
4. Once the draw completes, the manager opens the lottery results view
   (`GET /lottery_entries/concert/{concert_id}/results`) — every decided entry for the concert,
   winner and loser alike, each row already carrying the winner's email and their ticket's payment
   status/deadline, so no per-winner follow-up call is needed.
5. The winner calls `POST /tickets/{ticket_id}/checkout` before `payment_deadline_at` — creates the
   `Payment` and flips the ticket to `paid`; a `lottery_payment_confirmation` notification and
   email follow. The fan's ticket is now live. Paying after the deadline expires the ticket and
   releases the seat.

### 4. Buy a direct-sale ticket

1. The event page (`GET /concerts/{id}/detail`) lists the concert's tiers and campaigns; for a
   logged-in fan it also says whether they already hold a ticket or have lottery entries.
2. `POST /tickets/checkout` (3 requests per 60 s per user) with the ticket type, the expected
   amount (price + 10 % tax), the gateway and an idempotency key. Rejected unless a direct-sale
   campaign for the tier is open and inside its sale window, the tier has seats left, and the fan
   has no live ticket and no pending or won lottery entry for the concert.
3. With the mock gateway, a successful payment marks the ticket `paid`, counts the seat, and sends
   a `ticket_confirmation` notification and email in the same request; a declined payment cancels
   the ticket. With PayPal, the ticket stays `pending_payment` until the capture or webhook
   finalizes it.
4. `GET /tickets/mine` lists the fan's tickets.

### 5. Set up a concert for sale

A manager can only do this for their own company; an admin can do it for any company.

1. `POST /concerts/add` — title, venue, date, doors-open time and capacity (the venue itself is
   created by an admin).
2. `POST /concerts/performers/assign` — credit the performing groups and/or solo idols.
3. `POST /ticket_types/add` — one per tier: tier (VIP / premium / regular), price, number of seats,
   and sale method (`direct` or `lottery`). The tiers' seats can't add up to more than the
   concert's capacity.
4. For each tier, either `POST /direct_sale_campaigns/add` (a sale window) or
   `POST /lottery_campaigns/add` (an entry window and a payment deadline in hours).
5. For lottery tiers, once the entry windows close: run the draw and check the results
   (flow 3, steps 3–4).
6. `GET /tickets/concert/{concert_id}/sales` shows the tickets sold, newest first.

### 6. Ship an order

1. `GET /order/manager-orders-page` — orders containing the manager's company's products, newest
   first, showing only that company's line items.
2. `PATCH /order/{order_id}/ship` — moves the order's shipping status from `pending` or
   `processing` to `shipped` and sends the fan an `order_shipped` notification. Managers can only
   ship orders containing their company's products.

Known gap: shipping doesn't yet check that the order was actually paid, so an unpaid PayPal order
can be marked shipped (backend `docs/bugs.md` #26).
