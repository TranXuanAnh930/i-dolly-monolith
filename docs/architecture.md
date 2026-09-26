# Architecture and data flow

[← Back to README](../README.md)

## System

```
                      Cloudflare DNS (i-dolly-app.site)
                 ┌────────────────┴────────────────┐
                 ▼                                 ▼
   i-dolly-app.site (Vercel)          api.i-dolly-app.site (Render)
 ┌──────────────────────────┐        ┌───────────────────────────┐
 │ Frontend                 │  HTTPS │ Backend API               │
 │ Vue 3 + Vite + Pinia     │ ─────▶ │ FastAPI (Python 3.12)     │
 │ (i-dolly-frontend)       │  JSON  │ (i-dolly-backend)         │
 └──────────────────────────┘        └──────┬──────────┬─────────┘
                                            │          │
                                            ▼          ▼
                                ┌──────────────┐  ┌─────────────────────┐
                                │ PostgreSQL   │  │ Redis               │
                                │ (Supabase)   │  │ cache · rate limits │
                                └──────▲───────┘  │ Celery broker       │
                                       │          └──────────┬──────────┘
                                       │                     ▼
                                       │            ┌─────────────────┐
                                       └────────────│ Celery worker   │
                                                    │ lottery draw ·  │
                                                    │ email sending   │
                                                    └─────────────────┘

  External: PayPal (sandbox checkout + webhooks) · Resend (email from mail.i-dolly-app.site)
            · S3-compatible storage (idol/product images)
```

The frontend and backend are separate deployments that only talk over HTTP. The API lives on a
subdomain of the frontend's domain, so the refresh-token cookie is first-party rather than a
third-party cookie that Safari and Firefox would block.

## Inside the backend

Every feature follows the same three layers, inside a domain package (`identity/`, `talent/`,
`events/`, `marketplace/`, plus `shared/`):

| Layer | Location | Responsibility |
|---|---|---|
| Router | `app/router/<domain>/` | Declares the route, its dependencies (DB session, current user, rate limit) and response model; calls one service method; maps a `ServiceError` to its HTTP status |
| Service | `app/services/<domain>/` | Business rules, company scoping, row locks, transactions; raises `NotFoundError` / `ForbiddenError` / `BadRequestError` |
| Model / schema | `app/db/models/`, `app/schema/` | SQLAlchemy tables; Pydantic request and response models (responses are always separate classes from the ORM models) |

Cross-cutting pieces:

- **Route handlers are plain `def`.** SQLAlchemy, bcrypt, PayPal and boto3 calls are all
  synchronous, so FastAPI runs each handler in its threadpool instead of on the event loop. The one
  genuinely async step, reading the raw PayPal webhook body, is an async dependency.
- **Two error channels, one router pattern.** Service rule violations raise `ServiceError`
  subclasses. Database-trigger rejections are translated into `TriggerViolationError` subclasses by
  `commit_or_raise()` / `flush_or_raise()`. Both carry their own HTTP status code.
- **Cache split in two.** `app/cache/invalidation.py` holds the cache keys and `delete_cached_*`
  methods and depends only on Redis, so services can invalidate inside their own flows.
  `CacheService` (the read-through `get_cached_*` methods, which call services) inherits it and is
  only used by routers. That keeps imports one-directional.
- **Background work goes through Celery:** the lottery draw and every transactional email.

## Data flow

**A cached, rate-limited read** (e.g. `GET /products/store-page`):

```
Frontend → FastAPI router
             │
             ├─ rate_limit() dependency: Redis INCR on a route+identity key (expiry set when the
             │  key is created), 429 past the limit, fails OPEN if Redis itself errors
             │
             ├─ cache hit  → msgpack-decode the cached payload, return it — no DB query at all
             │
             └─ cache miss → service builds the response, validates it against the real
                response schema, msgpack-encodes + SETEX with a 5-minute TTL, returns it
```

Writes invalidate the affected keys right after they commit, so the TTL is a backstop, not the
freshness mechanism.

**Direct-sale ticket checkout with the mock gateway** (`POST /tickets/checkout`, 3 requests per
60 s per user):

1. Reject non-fans, a reused idempotency key, a tier that isn't in an open sale window, a sold-out
   tier, a fan who already holds a live ticket for the concert, and a fan with an unresolved
   lottery entry for it.
2. Lock the `ticket_types` row (`SELECT … FOR UPDATE`), check the amount (price + 10 % tax), and
   create the ticket and payment.
3. On a successful payment, increment `sold_quantity` and add a `ticket_confirmation`
   notification — all in one commit.
4. After the commit: invalidate the cached concert detail and queue the confirmation email.

**Ticket checkout with PayPal** — the flow that exercises locking, webhooks and cache invalidation
together:

1. `POST /tickets/checkout` creates a `pending_payment` ticket and a `pending` payment, asks PayPal
   to create an order, and commits. No seat is counted yet.
2. The frontend redirects the fan to PayPal's approval page; PayPal sends them back to
   `https://i-dolly-app.site/payment/paypal/return`.
3. The frontend calls `POST /payment/paypal/capture/{pg_order_id}`. PayPal may also call
   `POST /payment/paypal/webhook` (signature-verified) for the same payment. Both go through
   `finalize_paypal_payment()`.
4. That function locks the payment, ticket and ticket-type rows and returns early unless the
   payment is still `pending` — that check is the idempotency guard. It re-checks remaining stock,
   captures the payment with PayPal, then marks the payment `success` (storing PayPal's capture id,
   which refunds are issued against), the ticket `paid`, and increments `sold_quantity`, in one
   commit. A second caller finds a non-pending payment and does nothing.

Known gaps in this flow: the PayPal capture call runs while the row locks are held, and a capture
that succeeded at PayPal but failed to commit here isn't reconciled (backend `docs/bugs.md` #8). An
abandoned PayPal checkout leaves the ticket `pending_payment` with no expiry (#12, #27).

**Lottery draw** (`PUT /concerts/lottery-draw/{id}`): the router checks the manager's company,
notifies the company's managers that a draw started, and enqueues
`app.tasks.lottery.draw_lottery`. The worker locks the concert's ticket types, open campaigns and
pending entries; runs the rank cascade (see [Business logic](business-logic.md#lottery)); creates a
`pending_payment` ticket with a payment deadline for each winner; marks every other entry `lost`
and the campaigns `drawn`; commits once; then notifies the managers that it completed or failed.
Full sequence diagram:
[`database-design.md` §5.2](https://github.com/TranXuanAnh930/i-dolly-backend/blob/main/docs/database-design.md).
