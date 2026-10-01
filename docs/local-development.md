# Running both locally

[← Back to README](../README.md)

One `docker compose up` at the repo root starts the whole stack: the backend (API, Celery worker,
Postgres, Redis) and the frontend, built with Vite and served by nginx. The root
[`docker-compose.yaml`](../docker-compose.yaml) only includes each submodule's own compose file, so
every service is defined in one place.

Each app can still run on its own; see [Running each app on its own](#running-each-app-on-its-own).

## Prerequisites

- The submodules checked out: `git submodule update --init --recursive`
- Docker Desktop, or Docker Engine with Compose v2.20 or later (the root compose file uses `include`)
- Node.js 22+ and npm, only to run the frontend outside Docker (e.g. for hot reload or its tests)
- Python 3.12, only for running backend unit tests or ruff outside Docker

## 1. Configure the backend

```bash
cp i-dolly-backend/.env.example i-dolly-backend/.env
```

Before the first start, edit `i-dolly-backend/.env`. The root compose file reads it too, so there is
no separate `.env` at the root.

| Setting | What to put |
|---|---|
| `JWT_SECRET_KEY`, `JWT_REFRESH_SECRET_KEY`, `JWT_EMAIL_SECRET_KEY` | Three different random values: `python -c "import secrets; print(secrets.token_hex(32))"` |
| `DATABASE_URL`, `DATABASE_NAME`, `DATABASE_USER`, `DATABASE_PWD` | Matching values; the host in `DATABASE_URL` stays `postgres` (the compose service name) |
| `DEBUG` | `true` to print emails (including verification and reset links) to the console instead of sending them through Resend. Contact-page questions are also printed instead of being sent to Claude. It defaults to `false`. |
| `RESEND_API_KEY`, `FROM_EMAIL` | Any placeholder when `DEBUG=true`; a real key and a verified-domain address to actually send |
| `PAYPAL_*` | Optional. Leave empty and use the mock gateway, or add PayPal sandbox credentials |
| `ANTHROPIC_API_KEY` | Optional. Leave unset to turn off the contact page's instant answers, or add a Claude API key from the Claude Console. With a key and `DEBUG=false`, each question is a real, billed call (a fraction of a cent on Haiku 4.5) |

## 2. Start everything

From the repo root:

```bash
docker compose up --build
```

This starts five containers and runs the database migrations on boot:

| Service | Container | Port on your machine |
|---|---|---|
| `frontend` (nginx) | `i-dolly-monolith-frontend-1` | `8080` — open `http://localhost:8080` |
| `app` (FastAPI) | `i-dolly-backend` | `8000` — API docs at `http://localhost:8000/docs` |
| `worker` (Celery) | `i-dolly-worker` | — (runs the lottery draw and sends email) |
| `postgres` | `postgres_latest` | `5433` |
| `redis` | `redis` | `6379` |

The backend source is bind-mounted, so uvicorn restarts the API on every edit; rebuild (`--build`)
after changing `requirements.txt`. The frontend container serves a production build, so frontend
edits need a rebuild too. For hot reload while working on the frontend, run the
[frontend on its own](#frontend) next to this stack (stop the `frontend` service first, since both
use port `8080`: `docker compose stop frontend`).

The frontend bundle calls the API at `http://localhost:8000`, the API's published port, because the
browser rather than the container makes the API calls. Vite inlines this URL at build time; to point
at another backend, rebuild with it set, e.g.
`VITE_API_URL=https://api.example.com docker compose up --build`. The backend's default
`CORS_ORIGINS` already allows `http://localhost:8080`.

Stop with `docker compose down`; add `-v` to also delete the Postgres data volume.

The backend containers keep fixed names, so stop a stack started from `i-dolly-backend/` before
starting this one, and the other way round.

### Seed data

Optionally seed sample data — companies, groups, idols, venues, concerts, products and accounts for
each role. It's idempotent:

```bash
docker compose exec app python scripts/seed.py
```

Seeded logins include `admin@example.com`, `manager.nova@example.com` and `alex.fan@example.com`.
They all share one password: `SEED_PASSWORD` from the environment, or the default in
`scripts/seed.py`.

At checkout, choose the **mock** gateway to approve or decline a payment instantly, or **PayPal**
if the backend has sandbox credentials.

### Tests and lint

Integration tests use real Postgres and Redis, so run them inside the `app` container. They create
and migrate a separate `<database>_test` database first, so your development data isn't touched:

```bash
docker compose exec app python -m pytest tests/integration
```

The full integration suite takes several minutes; pass a folder or file to run part of it
(e.g. `tests/integration/events`).

Backend unit tests use mocks and an in-memory fake Redis, so they run outside Docker:

```bash
cd i-dolly-backend
pip install -r requirements-dev.txt
python -m pytest tests/unit
ruff check .
```

The frontend image only holds the built files, so run its tests and lint outside Docker:

```bash
cd i-dolly-frontend
npm ci
npm test
npm run lint
```

## Running each app on its own

### Backend

The backend submodule has its own compose file with the same four backend services:

```bash
cd i-dolly-backend
docker compose up --build
```

The commands above work the same way from this directory.

### Frontend

```bash
cd i-dolly-frontend
npm install
npm run dev
```

Starts the Vite dev server on `http://localhost:8080`. It targets the backend via
[`src/env.js`](https://github.com/TranXuanAnh930/i-dolly-frontend/blob/main/src/env.js), which
reads `VITE_API_URL` and falls back to `http://localhost:8000`, matching the backend's port, so no
config change is needed for local dev against a locally-running backend.

The frontend submodule also has its own `docker compose up --build` and a `Makefile` (`make` lists
the targets).

Full step-by-step (env vars, tests, linting) for each: their own READMEs,
[backend](https://github.com/TranXuanAnh930/i-dolly-backend#readme) and
[frontend](https://github.com/TranXuanAnh930/i-dolly-frontend#readme).
