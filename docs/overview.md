# Overview

[← Back to README](../README.md)

## What this is

Idols/groups, venues/concerts, lottery-based and direct-sale ticketing, and an album/merch
marketplace — reusing a forked e-commerce boilerplate's cart/order/payment/shipping machinery.
Role-based access (`admin`/`manager`/`fan`, company-scoped managers), in-app notifications
(order/ticket/lottery confirmations, lottery results, manager-facing lottery draw status, password
reset), a manager-triggered lottery draw run as a Celery background job with its own results view,
and PayPal checkout alongside a mock payment gateway for local dev. Full, current, honestly-scoped
feature list: [`i-dolly-backend/README.md`](https://github.com/TranXuanAnh930/i-dolly-backend#readme).

## Domains

The backend is split into four domain packages plus a shared one; every layer (router, service,
model, schema) follows the same split.

| Domain | Tables | What it covers |
|---|---|---|
| **Identity** | `users`, `refresh_tokens` | Registration, login, JWT access + rotating refresh tokens, email verification, password reset, roles |
| **Talent** | `management_companies`, `groups`, `idols`, `idol_colors`, `positions`, `idol_positions` | Agencies and their artists. Groups and idols are soft-deleted (`is_active`) so concert and product history survives |
| **Events & ticketing** | `venues`, `concerts`, `concert_performers`, `ticket_types`, `direct_sale_campaigns`, `lottery_campaigns`, `lottery_preferences`, `lottery_entries`, `tickets` | Concerts with capacity-based ticket tiers, sold either directly (in a sale window) or by lottery |
| **Marketplace** | `products`, `categories`, `album_details`, `merch_details`, `genres`, `album_genres`, `cart`, `orders`, `orders_items`, `payment`, `shipping_addresses`, `shipping_status` | Albums/singles/EPs and official merch: cart → checkout → payment → shipping |
| **Shared** | `notifications`, `inquiries` | In-app notifications for fans and managers; contact-form questions |

31 tables in total, built by one linear chain of Alembic migrations.

## Roles

| Role | Can do |
|---|---|
| **fan** | Browse everything; rank lottery tiers and apply; buy direct-sale tickets and pay for lottery wins; cart and checkout; read their own orders, tickets and notifications; ask questions through the contact page (guests can too) |
| **manager** | Belongs to one management company. Create and edit that company's groups, idols, concerts, ticket types, campaigns and products; trigger the lottery draw and view its results; view the company's orders and mark them shipped; view ticket and product sales |
| **admin** | Everything a manager can do, for every company; manage companies, venues and categories; create manager accounts and promote admins |

Managers and admins can't buy anything: cart, checkout, lottery entry and ticket purchase all
reject them. A manager's company scope is applied in the database query, not just hidden in the
UI. Details: [Business logic](business-logic.md).

## Features at a glance

- **Ticketing:** capacity-based tiers (VIP / premium / regular) per concert, each sold either
  directly during a direct-sale campaign window or through a lottery campaign; one live ticket per
  fan per concert across both paths.
- **Lottery:** fans rank the tiers they'd accept, apply during the entry window, and a manager runs
  the draw once entries close. The draw runs in a Celery worker; each winner gets a
  `pending_payment` ticket with a payment deadline.
- **Marketplace:** products with album or merch details, genres, a per-fan anti-resale cap
  (3 units per product), cart, checkout, shipping addresses, and a manager "Ship" action.
- **Payments:** a mock gateway (`simulate_succ` true/false) for local development and demos, and
  PayPal Orders v2 in sandbox mode (redirect approval, capture endpoint, signed webhook).
- **Notifications:** order confirmation and shipment, ticket confirmation, lottery registration,
  result, payment reminder and payment confirmation, manager-facing draw triggered / completed /
  failed, and password reset. (`event_reminder` is defined, but nothing sends it yet.)
- **Email:** Resend, sent from a Celery task so requests never wait on delivery.
- **Contact page (お問い合わせ):** a contact form open to guests and signed-in users. Each inquiry is
  saved and the sender gets a confirmation email that carries only the topic and a reference id,
  never their own text, capped at 3 per address per hour. Staff can't read inquiries in the app
  yet (see [Status and roadmap](status-and-roadmap.md)).
- **FAQ instant answers:** before sending the form, a fan's question can be answered from the site
  FAQ (English or Japanese) by the Claude API (`claude-haiku-4-5`). It answers only from the FAQ
  and otherwise returns "not answerable", so the contact form is always the fallback. Implemented
  and unit-tested, but not yet run against the real API.
- **Images:** idol and product uploads go to the local filesystem in development and to
  S3-compatible storage in production.
- **Contact page (お問い合わせ):** a question can first get an instant answer, written by Claude
  Haiku 4.5 using only the site FAQ (English or Japanese). If that doesn't help, the question is
  saved and a confirmation email goes to the sender. See
  [Use case flows](use-case-flows.md#7-ask-a-question--instant-faq-answer--contact-form).
- **Performance and abuse protection:** Redis cache for public and manager page bundles; Redis
  rate limiting on 68 routes.

## Tech stack

| Layer | Technology |
|---|---|
| API | Python 3.12, FastAPI 0.122, Pydantic 2.12, uvicorn 0.38 |
| Database | PostgreSQL (Supabase in production), SQLAlchemy 2.0, Alembic 1.17 |
| Cache, rate limiting, queue | Redis (msgpack-serialized cache); Celery 5.6 with Redis as broker and result backend |
| Auth | JWT (python-jose, HS256), bcrypt via passlib |
| Integrations | PayPal REST API (httpx), Resend, boto3 for S3-compatible storage, Anthropic Claude API (`anthropic` SDK, Claude Haiku 4.5) |
| Tests and CI | pytest — unit tests with an in-memory fake Redis, integration tests against real Postgres and Redis; ruff; GitHub Actions; Codecov |
| Frontend | Vue 3, Vite 5, Pinia, Vue Router 4, vue-i18n (`en`/`ja`), Axios, Sass |
| Hosting | Render (API, Celery worker, Key Value/Redis), Supabase, Vercel, Cloudflare DNS |

Full detail: [`i-dolly-backend/README.md`](https://github.com/TranXuanAnh930/i-dolly-backend#readme)
and [`i-dolly-frontend/README.md`](https://github.com/TranXuanAnh930/i-dolly-frontend#readme).
