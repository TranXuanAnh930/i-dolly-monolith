# Running both locally

[← Back to README](../README.md)

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

Full step-by-step (env vars, tests, linting) for each: their own READMEs,
[backend](https://github.com/TranXuanAnh930/i-dolly-backend#readme) and
[frontend](https://github.com/TranXuanAnh930/i-dolly-frontend#readme).
