# i-dolly-monolith

Umbrella repo for **I-Dolly** — an idol-concert **ticket reservation** platform with an
**album/singles marketplace**, built as a project to showcase full-stack engineering:
backend schema design/layered architecture/migration discipline/RBAC, and a Vue 3 SPA consuming
it. The backend and frontend are separate, independently-developed repos, wired in here as git
submodules — each keeps its own README, docs, CI, and deploy target; this file exists to give a
reviewer one place to land, not to duplicate what's already documented in either one.

**Not a production system.** Both submodules say plainly, in their own docs, what's unfinished —
see each one's "Known limitations"/"Project status" section before assuming a feature is done.


**🚀 Live Demo** 

**Frontend:** i-dolly-frontend.vercel.app

**API:** https://i-dolly-backend.onrender.com

**API Documentation:** https://i-dolly-backend.onrender.com/docs

---

## Layout

This is a submodule-based monorepo, not a shared codebase — backend and frontend never import
from each other, they only talk over HTTP:

- [`i-dolly-backend/`](https://github.com/TranXuanAnh930/i-dolly-backend) — FastAPI + PostgreSQL +
  Redis + Celery API
- [`i-dolly-frontend/`](https://github.com/TranXuanAnh930/i-dolly-frontend) — Vue 3 + Vite + Pinia
  SPA

### Clone

```bash
git clone --recurse-submodules https://github.com/TranXuanAnh930/i-dolly-monolith.git
```

Already cloned without `--recurse-submodules`?

```bash
git submodule update --init --recursive
```

Each submodule is pinned to a specific commit of its own repo — `git submodule update --remote`
(inside a submodule, or with `--remote` at the top level) to pull the latest from that submodule's
own `main`.

---

## What this is

Idols/groups, venues/concerts, lottery-based and direct-sale ticketing, and an album/merch
marketplace — reusing a forked e-commerce boilerplate's cart/order/payment/shipping machinery.
Role-based access (`admin`/`manager`/`fan`, company-scoped managers), in-app notifications
(order/ticket/lottery confirmations, lottery results, password reset), a manager-triggered lottery
draw run as a Celery background job, and PayPal checkout alongside a mock payment gateway for
local dev. Full, current, honestly-scoped feature list:
[`i-dolly-backend/README.md`](https://github.com/TranXuanAnh930/i-dolly-backend#readme).

## Architecture

```
┌────────────────────────┐   HTTP/REST   ┌──────────────────────────┐
│        Frontend          │ ───────────▶ │         Backend           │
│  Vue 3 + Vite + Pinia    │               │   FastAPI (Python 3.12)  │
│  (i-dolly-frontend)      │               │   (i-dolly-backend)      │
└────────────────────────┘               └──────────┬───┬───────────┘
                                                       │   │
                                      ┌────────────────┘   └────────────────┐
                                      ▼                                     ▼
                             ┌────────────────┐                   ┌──────────────────┐
                             │   PostgreSQL    │                   │      Redis        │
                             │   (Supabase)    │                   │ cache / rate      │
                             └────────────────┘                   │ limiter / Celery  │
                                                                    │ broker+backend    │
                                                                    └─────────┬─────────┘
                                                                              ▼
                                                                     Celery worker
                                                                   (lottery draw job)

  External services: SendGrid (email) · PayPal Sandbox (checkout) · S3-compatible storage (images)
```

## Data flow

Two request shapes cover most of what this system does — a plain cached read, and the async
payment flow every checkout goes through.

**A cached, rate-limited read** (e.g. `GET /products/store-page`):

```
Frontend → FastAPI router
             │
             ├─ rate_limit() dependency: atomic Redis INCR on a route+identity key, 429 past the
             │  limit, fails OPEN (request proceeds) if Redis itself errors
             │
             ├─ cache hit  → msgpack-decode the cached payload, return it — no DB query at all
             │
             └─ cache miss → service layer builds the response, Pydantic-validates it against the
                real response schema, msgpack-encodes + SETEXs it with a TTL, returns it
```

**Ticket checkout with PayPal** — the flow that actually exercises concurrency, webhook handling,
and cache invalidation together, end to end:

1. Fan hits `POST /tickets/checkout` (rate-limited 3/60s per user — inventory/money, not a free
   read). The service takes a row lock on the `ticket_type` (`SELECT ... FOR UPDATE`), checks
   remaining stock *under that lock*, creates a `pending_payment` Ticket row, asks PayPal to create
   an order, and commits once — no stock is decremented yet, deliberately.
2. The frontend redirects the fan to PayPal's hosted approval page; PayPal redirects back with a
   token once they approve.
3. The frontend calls `POST /payment/paypal/capture/{pg_order_id}`. Independently, on no fixed
   schedule, PayPal also calls `POST /payment/paypal/webhook` to reconcile the same payment — not a
   bug in either path, just how PayPal's async model works — and both endpoints funnel into the
   exact same `finalize_paypal_payment()` function rather than duplicating the logic twice.
4. Whichever of the two calls arrives first re-acquires the row lock, checks the payment is still
   `pending` (that check *is* the idempotency guard — no separate "have I seen this event before"
   table needed), decrements stock, captures the payment with PayPal, marks everything paid, and
   commits once. The call that loses that race sees a non-pending payment and quietly no-ops
   instead of double-charging or double-issuing a ticket.

The lottery side follows the same "lock, check under the lock, write, commit once" shape but with
an extra actor: a manager's `PUT /concerts/lottery-draw/{id}` only validates RBAC and enqueues a
Celery task (`app.tasks.lottery.draw_lottery`) rather than running the rank-cascade draw inline —
the algorithm itself locks every affected `ticket_types`/`lottery_campaigns`/`lottery_entries` row
for that concert before touching any of them. Full sequence diagram:
[`database-design.md` §5.2](https://github.com/TranXuanAnh930/i-dolly-backend/blob/main/docs/database-design.md).

## Under the hood: notable engineering decisions

The backend README covers *what's* built; these are the *why* behind a few choices a reviewer
skimming the code might otherwise read as either over- or under-engineered.

**Concurrency — one row-locking pattern, reused everywhere money or inventory is at stake.**
Checkout (`order_service.checkout`), ticket purchase (`ticket_service.checkout_ticket`), and the
lottery draw (`lottery_draw_service.draw_lottery`) all follow the same shape: take a
`with_for_update()` lock on every row the operation will read-then-write, check the business rule
*while holding the lock*, do the writes, commit exactly once at the end — never commit partway
through, and never check a condition before the lock that could still change before the write
lands. The checkout path locks every affected `Product` row in a fixed order (by primary key)
specifically so two concurrent checkouts touching an overlapping cart can't deadlock each other by
acquiring the same two rows in opposite order.

**Rate limiting — atomic by construction, fails open on purpose.**
It's a single atomic Redis `INCR` (creates the key at 1 on first use, increments
otherwise), with the expiry set only by whichever request just created the window. If Redis itself is
unreachable, the limiter logs and lets the request through rather than 500ing every rate-limited
route (36 of them, including login) — availability matters more than the limiter working during an
outage, and failing closed wouldn't add real security anyway, since whatever caused the outage
evades the limiter either way. Behind Render's reverse proxy, the raw connecting IP is Render's own
edge for every visitor, which would collapse everyone into one shared bucket — fixed at the
transport layer with uvicorn's `ProxyHeadersMiddleware` rather than hand-parsing
`X-Forwarded-For`, since that header is client-settable and a naive parse would let an attacker
mint a fresh rate-limit bucket on every request just by sending a new fake value.

**Webhook handling — no event-id ledger, because the domain already gives idempotency for free.**
The original plan was a `processed_webhook_events` table keyed on PayPal's event id. It turned out
unnecessary: `finalize_paypal_payment` only ever does real work when `payment.status == pending`,
and a payment's status only ever leaves `pending` once — so whether PayPal's webhook fires before,
after, or instead of the frontend's own capture call, or fires the same event twice (which webhooks
are explicitly allowed to do), the second caller to reach that function always finds a non-pending
payment and no-ops.

**Caching — invalidated on write, not just time-boxed, and validated through the real schema.**
Redis holds two keys today (`products:list`, `products:store_page`), msgpack-serialized with a
5-minute TTL. The TTL alone would eventually self-correct, but a purchase lowering
`Product.quantity` used to leave the cached list stale for up to 5 minutes after a real stock
change — fixed by having checkout (both the mock-gateway and PayPal paths) explicitly delete both
cache keys the moment a payment actually succeeds, gated on the same success condition that gates
the stock decrement itself, so a declined or still-pending payment never invalidates a cache that
hasn't actually gone stale. The store-page cache is built by validating the real response Pydantic
model and dumping *that*, rather than hand-typing a second parallel dict shape next to the schema —
so a field renamed on the schema fails loudly the next time the cache is written, instead of
silently drifting out of sync with what the endpoint's `response_model` actually promises.


## Tech stack

**Backend** — FastAPI, Pydantic v2, PostgreSQL via SQLAlchemy 2.0 + Alembic, Redis
(caching + rate limiting), Celery, JWT auth, SendGrid, PayPal + a mock payment gateway, local/S3
image storage, Docker Compose, GitHub Actions CI (ruff lint + pytest/coverage). Full detail:
[`i-dolly-backend/README.md`](https://github.com/TranXuanAnh930/i-dolly-backend#readme).

**Frontend** — Vue 3 (Composition/Options API), Vite, Pinia, Vue Router 4, vue-i18n (`en`/`ja`),
Axios, Sass. Full detail:
[`i-dolly-frontend/README.md`](https://github.com/TranXuanAnh930/i-dolly-frontend#readme).

## Running both locally

The two apps run independently — there's no shared docker-compose at this level; each submodule
has its own.

### 1. Backend

```bash
cd i-dolly-backend
cp .env.example .env
docker compose up --build
```

Fill in `.env` with at least a JWT secret first. This starts FastAPI + PostgreSQL + Redis + a
Celery worker and runs migrations on boot. API docs: `http://localhost:8000/docs`. Optionally seed
sample data (idempotent):

```bash
docker compose exec app python scripts/seed.py
```

### 2. Frontend

```bash
cd i-dolly-frontend
npm install
npm run dev
```

Starts the Vite dev server on `http://localhost:8080`. It targets the backend via
[`src/env.js`](https://github.com/TranXuanAnh930/i-dolly-frontend/blob/main/src/env.js), which
defaults to `http://localhost:8000` — matching the backend's default above, so no config change is
needed for local dev against a locally-running backend.

Full step-by-step (env vars, tests, linting) for each: their own READMEs, linked above.

---

## Documentation

Each submodule owns its own docs; nothing here duplicates them — read the submodule's copy, not a
mirror, since only that copy is kept current:

| Repo | Docs |
|---|---|
| Backend | [`database-design.md`](https://github.com/TranXuanAnh930/i-dolly-backend/blob/main/docs/database-design.md) (schema/ERD/RBAC/lottery logic), [`architecture.md`](https://github.com/TranXuanAnh930/i-dolly-backend/blob/main/docs/architecture.md) (code layering/conventions), [`project_status.md`](https://github.com/TranXuanAnh930/i-dolly-backend/blob/main/docs/project_status.md) (built vs. open, known issues), [`api-spec.md`](https://github.com/TranXuanAnh930/i-dolly-backend/blob/main/docs/api-spec.md) (every route), [`deployment.md`](https://github.com/TranXuanAnh930/i-dolly-backend/blob/main/docs/deployment.md) |
| Frontend | [`architecture.md`](https://github.com/TranXuanAnh930/i-dolly-frontend/blob/main/docs/architecture.md), [`business_logic.md`](https://github.com/TranXuanAnh930/i-dolly-frontend/blob/main/docs/business_logic.md) |

## Deployment

- **Backend**: Render (API + a Background Worker for Celery), Supabase (Postgres), an
  S3-compatible bucket (image uploads), Render's Key Value add-on (Redis) — see
  `i-dolly-backend/docs/deployment.md`.
- **Frontend**: Vercel — `vercel.json` rewrites every route to `index.html` for client-side
  routing; the deployed API URL is supplied at build time via `VITE_API_URL`.

## Known limitations

Read each submodule's own current list rather than trusting a summary here, — start with
[`i-dolly-backend/README.md#known-limitations`](https://github.com/TranXuanAnh930/i-dolly-backend#known-limitations)
and its `docs/project_status.md`. In short: this is a portfolio project verified mostly through
static analysis and targeted live-DB sessions rather than continuous production traffic, in both
halves — treat it accordingly.

## Future work

Flagged as planned, not started — named here rather than designed speculatively:

- **OLAP migration** — the ETL/analytics pipeline flagged as not-yet-started in
  `i-dolly-backend/docs/project_status.md` §5: an event-sourced outbox (`domain_events`: type,
  payload, occurred_at, processed) written in the same transaction as each business event (ticket
  purchases, lottery entries/draws, payment/shipment status changes), transformed downstream into
  analytics-friendly fact tables (`fact_sales_by_concert`, `fact_lottery_conversion`,
  `fact_fan_activity`) — either a separate schema in the same Postgres instance or a dedicated OLAP
  store, depending on scope once the OLTP shape settles further.
- **Go benchmarking** — a standalone Go load-testing tool against the FastAPI backend, to get real
  concurrent-throughput/latency numbers (checkout's stock-lock contention, the lottery draw, the
  rate limiter under burst traffic) rather than relying on `pytest`'s correctness-only coverage.
  Not started; which endpoints and load profile to target is still undecided.

## License

Proprietary — all rights reserved, matching both submodules.
