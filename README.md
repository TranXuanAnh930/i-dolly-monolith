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

- **Cache & rate limiter fixes** — closing the gaps already recorded in
  [`i-dolly-backend/README.md#known-limitations`](https://github.com/TranXuanAnh930/i-dolly-backend#known-limitations)
  and `docs/project_status.md` (§4 item 2, item 21): swap the rate limiter's non-atomic
  `GET`-then-`SETEX`/`INCR` sequence for one atomic `INCR`, so concurrent requests can't race past
  the limit; fail open (not 500) when Redis itself is unreachable; handle `X-Forwarded-For`/
  `X-Real-IP` for `ip_key` behind a reverse proxy (Render/Docker/nginx).
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
