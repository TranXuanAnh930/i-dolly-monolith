# Overview

[← Back to README](../README.md)

## What this is

Idols/groups, venues/concerts, lottery-based and direct-sale ticketing, and an album/merch
marketplace — reusing a forked e-commerce boilerplate's cart/order/payment/shipping machinery.
Role-based access (`admin`/`manager`/`fan`, company-scoped managers), in-app notifications
(order/ticket/lottery confirmations, lottery results, manager-facing lottery draw status, password
reset), a manager-triggered lottery draw run as a Celery background job with its own results view,
and PayPal checkout alongside a mock payment gateway for local dev. Full, current, honestly-scoped feature list:
[`i-dolly-backend/README.md`](https://github.com/TranXuanAnh930/i-dolly-backend#readme).

## Tech stack

**Backend** — FastAPI, Pydantic v2, PostgreSQL via SQLAlchemy 2.0 + Alembic, Redis
(caching + rate limiting), Celery, JWT auth, Resend, PayPal + a mock payment gateway, local/S3
image storage, Docker Compose, GitHub Actions CI (ruff lint + pytest/coverage). Full detail:
[`i-dolly-backend/README.md`](https://github.com/TranXuanAnh930/i-dolly-backend#readme).

**Frontend** — Vue 3 (Composition/Options API), Vite, Pinia, Vue Router 4, vue-i18n (`en`/`ja`),
Axios, Sass. Full detail:
[`i-dolly-frontend/README.md`](https://github.com/TranXuanAnh930/i-dolly-frontend#readme).
