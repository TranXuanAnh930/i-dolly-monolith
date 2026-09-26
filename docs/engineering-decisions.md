# Engineering decisions

[← Back to README](../README.md)

The backend README covers *what's* built; these are the *why* behind a few choices a reviewer
skimming the code might otherwise read as either over- or under-engineered.

- [Concurrency: one row-locking pattern](#concurrency)
- [Business rules enforced twice: service first, trigger as backstop](#rules-enforced-twice)
- [Synchronous route handlers](#sync-handlers)
- [Rate limiting](#rate-limiting)
- [Webhook handling](#webhooks)
- [Caching](#caching)
- [Lottery notifications](#lottery-notifications)
- [Soft deletes](#soft-deletes)

<a id="concurrency"></a>
**Concurrency — one row-locking pattern, reused everywhere money or inventory is at stake.**
Checkout (`order_service.checkout`), ticket purchase (`ticket_service.checkout_ticket`), and the
lottery draw (`lottery_draw_service.draw_lottery`) all follow the same shape: take a
`with_for_update()` lock on every row the operation will read-then-write, check the business rule
*while holding the lock*, do the writes, commit exactly once at the end — never commit partway
through, and never check a condition before the lock that could still change before the write
lands. The checkout path locks every affected `Product` row in a fixed order (by primary key)
specifically so two concurrent checkouts touching an overlapping cart can't deadlock each other by
acquiring the same two rows in opposite order.

Operations that only need the lottery campaigns to *stay put* take a weaker lock. Applying to a
lottery and changing a tier ranking load the campaign rows `FOR SHARE`: many fans can apply at once
without blocking each other, but the draw's `FOR UPDATE` has to wait for them, and an apply that
arrives mid-draw waits for the draw, then sees the campaign as `drawn` and is rejected. Without
that lock, an entry could land after the draw and stay `pending` forever. Integration tests race
each of these against a real Postgres, and fail if the lock is removed.

One detail that bit once: when a row has already been loaded into the SQLAlchemy session before
it's locked, the locking query must use `populate_existing()`, or the session hands back the stale,
unlocked copy and the check runs against old data.

<a id="rules-enforced-twice"></a>
**Business rules enforced twice: service first, trigger as backstop.** Every rule that protects
money or a scarce seat (fan-only purchases, one ticket per concert, ticket capacity, the resale cap,
lottery entry rules) is checked in the service, where it can return a clear message, and again by a
Postgres trigger, so it holds against a bug in a new code path or a direct database write. The
backend translates each trigger's `RAISE EXCEPTION` text into a typed exception with its own HTTP
status, so a trigger rejection reaches the client as a clean 400/403 rather than a 500. The full
list is in [Business logic](business-logic.md#rules-and-where-theyre-enforced).

<a id="sync-handlers"></a>
**Synchronous route handlers, on purpose.** Every route handler is a plain `def`, not
`async def`. The stack below them — SQLAlchemy sessions, bcrypt, the PayPal HTTP client, boto3 — is
synchronous, and FastAPI runs `def` handlers in a threadpool, so a slow database query or PayPal
call only occupies one worker thread. The same code inside `async def` would run on the event loop
and stall every other request in the process; in a small standalone benchmark, five concurrent
one-second blocking requests took 5 s under `async def` versus 1 s under `def`. The one step that really is async, reading the raw PayPal webhook
body, is an async dependency that the synchronous handler receives as bytes.

<a id="rate-limiting"></a>
**Rate limiting — a fixed window in Redis, failing open on purpose.**
Each request increments a Redis counter keyed by the route template plus either the user id or the
client IP (`INCR`, with the expiry set by the request that created the window). If Redis itself is
unreachable, the limiter logs and lets the request through rather than 500ing every rate-limited
route (62 of them, including login) — availability matters more than the limiter working during an
outage, and failing closed wouldn't add real security anyway, since whatever caused the outage
evades the limiter either way. Two known gaps (backend `docs/bugs.md`): the increment and the expiry
are two separate Redis calls, so a crash between them could leave a counter that never expires
(#22); and IP-keyed limits can be bypassed (#7). Behind Render's reverse proxy, the raw connecting
IP is Render's own edge for every visitor, which would collapse everyone into one shared bucket.
uvicorn's `ProxyHeadersMiddleware` restores per-visitor IPs from `X-Forwarded-For`, but with
`trusted_hosts="*"` it reads the header's leftmost entry, which the client writes — so an attacker
can still mint a fresh bucket per request with a fake value. **Fix planned:** read the entry our own
proxies appended (counting from the right) and add a per-account limit on failed logins — see
[`docs/plans/rate-limit-client-ip.md`](https://github.com/TranXuanAnh930/i-dolly-backend/blob/main/docs/plans/rate-limit-client-ip.md).

<a id="webhooks"></a>
**Webhook handling — no event-id ledger, because the domain already gives idempotency for free.**
The original plan was a `processed_webhook_events` table keyed on PayPal's event id. It turned out
unnecessary: `finalize_paypal_payment` only ever does real work when `payment.status == pending`,
and a payment's status only ever leaves `pending` once — so whether PayPal's webhook fires before,
after, or instead of the frontend's own capture call, or fires the same event twice (which webhooks
are explicitly allowed to do), the second caller to reach that function always finds a non-pending
payment and no-ops. Authenticity is checked by posting the event back to PayPal's own
verify-webhook-signature API rather than re-implementing its certificate checks. Order events
(`CHECKOUT.ORDER.*`) and capture events (`PAYMENT.CAPTURE.*`) carry the order id in different
places; the handler reads either, and acknowledges any other event with a 200 so PayPal doesn't
retry it for days.

<a id="caching"></a>
**Caching — invalidated on write, not just time-boxed, and validated through the real schema.**
What started as two product-list keys now covers every unauthenticated page-shaped read and every
manager/admin settings page: the store grid, events/members/groups grids, venues/idol-colors
lookups, and the manager idols/idol-form/groups/events/products/product-form pages plus the
management-company list — all msgpack-serialized with a 5-minute TTL, all invalidated on write
rather than left to expire. The TTL alone would eventually self-correct, but a purchase lowering
`Product.quantity`, or a manager editing a group, used to leave the cached page stale for up to 5
minutes after the real change — fixed by having every mutating endpoint explicitly delete the
cache key(s) it affects right after its write commits, gated on the same success condition that
gates the underlying write itself, so a declined or still-pending write never invalidates a cache
that hasn't actually gone stale. Two follow-on problems that only show up once caching covers more
than one table:
- **Cross-domain invalidation.** A group's cached page embeds a computed `member_count`; an idol
  moving into or out of that group changes the count without touching the `groups` table at all.
  Idol writes invalidate the groups cache too (and vice versa for the members page's group filter)
  — same reasoning, applied wherever one cached page's numbers depend on another table's rows.
- **Scoped keys, not one shared key.** The manager products pages are scoped by `company_id` (a
  manager only ever sees their own company's catalog; an admin sees everything). Caching that with
  one shared key would leak one company's cached page into another's request, or into the admin's
  unfiltered view — so it's one Redis key per `company_id`, with invalidation clearing every
  company's key on a write rather than computing which single one a given product write actually
  touched (`company_id` isn't a column on `Product` itself; it's resolved indirectly through
  `album_details`/`merch_details`, so knowing exactly which key to clear isn't cheap — clearing all
  of them is).

Every cached page is built by validating the real response Pydantic model and dumping *that*,
rather than hand-typing a second parallel shape next to the schema — so a field renamed on the
schema fails loudly the next time the cache is written, instead of silently drifting out of sync
with what the endpoint's `response_model` actually promises.

The concert detail page is cached without anything viewer-specific; whether *this* fan already has
a ticket, won a lottery or ranked tiers is computed per request and merged in afterwards, so one
fan's state is never cached and served to another.

The cache code is split in two to avoid an import cycle: the key names and `delete_cached_*`
methods live in a module that depends only on Redis, which services import to invalidate inside
their own flows (checkout, payment, the draw). The read-through `get_cached_*` methods, which call
services to rebuild a page, inherit from it and are only used by routers.

<a id="lottery-notifications"></a>
**Lottery notifications — three manager-facing signals for a fire-and-forget job, and why win/loss
email was cut.** `PUT /concerts/lottery-draw/{id}` only enqueues a Celery task and returns
immediately — the router never gets the actual draw result back, so the only way a manager learns
what stage a draw is in is three separate in-app notifications: `lottery_draw_triggered` (the
moment the button is pressed), `lottery_draw_failed` (the task raised — a closed-campaign race from
a double-click, entries not closed yet, a real bug — caught, notified, then re-raised so Celery's
own `FAILURE` state still reflects it too, not just the notification), and `lottery_draw_completed`
(the draw's own commit landed). None of the three carry per-winner detail — that's what the results
view in the [lottery use case flow](use-case-flows.md) is for. Fans still get an in-app `lottery_result` notification each
way, plus `lottery_payment_reminder` for winners, but no email: `LOTTERY_WON`/`LOTTERY_LOST`
templates existed early on and were deliberately removed once testing against real seed-fan
addresses meant every test draw was sending real win/loss email; `lottery_payment_confirmation` (an
actual payment succeeding) kept its email, since payment/ticket confirmation is the event actually
worth an inbox notification here, not "how the draw came out." Separately, the Celery task's return
value has to be `.model_dump(mode="json")`'d rather than returned as the raw `LotteryResult`
Pydantic model — Celery's JSON result serializer can't encode an arbitrary model, and shipping the
raw object once had the draw finish successfully in the database while Celery itself logged and
recorded the task as a `FAILURE`, purely from that encode step failing after the real work was
already done.

Confirmation emails are queued only after the transaction commits. Queuing them before the commit
would email a fan about a ticket whose purchase then rolled back.

<a id="soft-deletes"></a>
**Soft deletes where history points at the row.** Groups and idols are deactivated
(`is_active = false`) and concerts are cancelled instead of deleted: tickets, lottery entries,
concert credits and products all reference them, and a hard delete would either cascade away that
history or orphan it. Deactivated artists disappear from public pages but stay loadable in manager
forms so they can be reactivated. Products don't follow this rule yet — deleting one still cascades
into past order lines (backend `docs/bugs.md` #2).
