# Running both locally

[← Back to README](../README.md)

The two apps run independently — there's no shared docker-compose at this level; each submodule
has its own.

## Prerequisites

- Docker Desktop (for the backend's Postgres, Redis, API and Celery worker)
- Node.js and npm (for the frontend)
- Python 3.12 (only for running backend unit tests or ruff outside Docker)

## 1. Backend

```bash
cd i-dolly-backend
cp .env.example .env
docker compose up --build
```

Before the first start, edit `.env`:

| Setting | What to put |
|---|---|
| `JWT_SECRET_KEY`, `JWT_REFRESH_SECRET_KEY`, `JWT_EMAIL_SECRET_KEY` | Three different random values: `python -c "import secrets; print(secrets.token_hex(32))"` |
| `DATABASE_URL`, `DATABASE_NAME`, `DATABASE_USER`, `DATABASE_PWD` | Matching values; the host in `DATABASE_URL` stays `postgres` (the compose service name) |
| `DEBUG` | `true` to print emails (including verification and reset links) to the console instead of sending them through Resend. It defaults to `false`. |
| `RESEND_API_KEY`, `FROM_EMAIL` | Any placeholder when `DEBUG=true`; a real key and a verified-domain address to actually send |
| `PAYPAL_*` | Optional. Leave empty and use the mock gateway, or add PayPal sandbox credentials |

`docker compose up` starts four containers and runs the database migrations on boot:

| Service | Container | Port on your machine |
|---|---|---|
| `app` (FastAPI) | `i-dolly-backend` | `8000` — API docs at `http://localhost:8000/docs` |
| `worker` (Celery) | `i-dolly-worker` | — (runs the lottery draw and sends email) |
| `postgres` | `postgres_latest` | `5433` |
| `redis` | `redis` | `6379` |

Optionally seed sample data — companies, groups, idols, venues, concerts, products and accounts for
each role. It's idempotent:

```bash
docker compose exec app python scripts/seed.py
```

Seeded logins include `admin@example.com`, `manager.nova@example.com` and `alex.fan@example.com`.
They all share one password: `SEED_PASSWORD` from the environment, or the default in
`scripts/seed.py`.

### Tests and lint

Unit tests use mocks and an in-memory fake Redis, so they run outside Docker:

```bash
pip install -r requirements-dev.txt
python -m pytest tests/unit
ruff check .
```

Integration tests use real Postgres and Redis, so run them inside the `app` container. They create
and migrate a separate `<database>_test` database first, so your development data isn't touched:

```bash
docker compose exec app python -m pytest tests/integration
```

The full integration suite takes several minutes; pass a folder or file to run part of it
(e.g. `tests/integration/events`).

## 2. Frontend

```bash
cd i-dolly-frontend
npm install
npm run dev
```

Starts the Vite dev server on `http://localhost:8080`. It targets the backend via
[`src/env.js`](https://github.com/TranXuanAnh930/i-dolly-frontend/blob/main/src/env.js), which
reads `VITE_API_URL` and falls back to `http://localhost:8000` — matching the backend's default
above, so no config change is needed for local dev against a locally-running backend. The
backend's default `CORS_ORIGINS` already allows `http://localhost:8080`.

At checkout, choose the **mock** gateway to approve or decline a payment instantly, or **PayPal**
if the backend has sandbox credentials.

Full step-by-step (env vars, tests, linting) for each: their own READMEs,
[backend](https://github.com/TranXuanAnh930/i-dolly-backend#readme) and
[frontend](https://github.com/TranXuanAnh930/i-dolly-frontend#readme).
