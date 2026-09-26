# Use case flows

[← Back to README](../README.md)

Multi-step journeys spanning several endpoints — each request is stateless; every step below is a
separate HTTP call, tied together only by tokens/ids the previous step handed back.

**1. Forgot password → reset it → log back in**

1. `POST /profile/forgot-password` — always returns the same generic message whether or not the
   email is registered, so the endpoint can't be used to enumerate accounts. If it is registered,
   `reset_password_process` mints a short-lived JWT reset token (`EMAIL_TOKEN_EXPIRE_MINUTES`) and
   queues an email carrying it through Celery (`celery_app.send_task`), like every other email.
2. The fan reads the token from that email (or the console, in local dev where `DEBUG=true` prints
   it instead of calling Resend) and calls `POST /profile/set-password` with
   `{token, new_password}`. This revokes every existing refresh token for the account — a session
   an attacker already held doesn't survive the reset meant to lock them out — and writes an
   in-app `password_reset` notification.
3. `POST /account/login` with the new password — ordinary login, a fresh access/refresh token
   pair.

**2. Add to cart → checkout → notified on two channels**

1. `POST /cart/add_cart` — no side effects beyond the cart row itself.
2. `POST /order/checkout` — locks every affected `Product` row (fixed id order, deadlock-safe),
   checks stock and the resale cap under that lock, creates `Order`/`OrderItem`/`Payment` in one
   commit. Only on a successful payment does that same commit also decrement stock, clear the
   cart, and write an in-app `order_confirmation` notification; the product-list/store-page cache
   is invalidated right after, once the commit lands.
3. Back in the router, once `checkout()` returns without the order having been cancelled outright
   (a declined mock payment cancels it immediately — no confirmation email for that case): an
   `EmailTemplate.ORDER_PLACED` email is dispatched via `celery_app.send_task(...)`, off the
   request/response cycle entirely, picked up whenever the Celery worker gets to it.

**3. Lottery entry → manager-triggered draw → win → pay → ticket in hand**

1. `POST /lottery_preferences/set` — the fan ranks tiers for a concert (1st VIP, 2nd Premium, …).
2. `POST /lottery_entries/apply` — free, no cart, no payment; rejected if the fan already holds a
   live ticket for that concert, or hasn't ranked the tier they're applying to.
3. A manager calls `PUT /concerts/lottery-draw/{id}`, which only validates RBAC and enqueues
   `app.tasks.lottery.draw_lottery` — the actual rank-cascade draw runs inside the Celery worker,
   locking every affected `ticket_type`/`lottery_campaign`/`lottery_entry` row for that concert
   before touching any of them. A win inserts a `pending_payment` Ticket row and reserves the seat
   (`ticket_types.sold_quantity += 1`) immediately, before any money moves; a loss writes nothing to
   inventory at all. (Which notifications fire around this step, and why win/loss email was cut —
   see [Engineering decisions](engineering-decisions.md#lottery-notifications).)
4. Once the draw completes, the manager opens the lottery results view
   (`GET /lottery_entries/concert/{concert_id}/results`) — every decided entry for the concert,
   winner and loser alike, each row already carrying the winner's email and their ticket's payment
   status/deadline, so no per-winner follow-up call is needed.
5. The winner calls `POST /tickets/{ticket_id}/checkout` before `payment_deadline_at` — creates the
   `Payment` and flips the ticket to `paid`. The fan's ticket is now live.
