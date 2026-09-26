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

Note: Render's free and lower-tier instances spin down after 15 minutes of inactivity, causing an initial cold-start loading time of about 30 to 50 seconds (and sometimes up to a minute) for the first incoming request. So the first time visiting the website, it can takes up around 50 seconds.  

**Frontend:** https://i-dolly-app.site

**API:** https://api.i-dolly-app.site

**API Documentation:** https://api.i-dolly-app.site/docs

<img width="1919" height="1030" alt="image" src="https://github.com/user-attachments/assets/8480700a-cecc-4360-865b-7f151fd360ec" />


<img width="1918" height="1013" alt="image" src="https://github.com/user-attachments/assets/a4502c75-a702-4325-9dec-034a520b6772" />

---

## Contents

| Doc | What's inside |
|---|---|
| [Overview](docs/overview.md) | Domains and their tables, roles, features, tech stack with versions |
| [Architecture and data flow](docs/architecture.md) | System diagram, backend layering, cached reads, mock and PayPal checkout, the lottery draw |
| [Business logic](docs/business-logic.md) | Every rule and whether a database trigger backs it up, the lottery algorithm, status lifecycles |
| [Use case flows](docs/use-case-flows.md) | Six journeys endpoint by endpoint: password reset, checkout, lottery, direct-sale ticket, concert setup, shipping |
| [Engineering decisions](docs/engineering-decisions.md) | Why: row and share locks, trigger backstops, sync handlers, rate limiting, webhooks, caching, notifications, soft deletes |
| [Running both locally](docs/local-development.md) | Setup, `.env` essentials, ports, seed data, running tests |
| [Deployment](docs/deployment.md) | What runs where, DNS records, cross-service settings, CI/CD |
| [Status and roadmap](docs/status-and-roadmap.md) | Known limitations, how it's tested, open issues, future work |

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

## Submodule documentation

Each submodule owns its own docs; nothing here duplicates them — read the submodule's copy, not a
mirror, since only that copy is kept current:

| Repo | Docs |
|---|---|
| Backend | [`database-design.md`](https://github.com/TranXuanAnh930/i-dolly-backend/blob/main/docs/database-design.md) (schema/ERD/RBAC/lottery logic), [`architecture.md`](https://github.com/TranXuanAnh930/i-dolly-backend/blob/main/docs/architecture.md) (code layering/conventions), [`project_status.md`](https://github.com/TranXuanAnh930/i-dolly-backend/blob/main/docs/project_status.md) (built vs. open, known issues), [`api-spec.md`](https://github.com/TranXuanAnh930/i-dolly-backend/blob/main/docs/api-spec.md) (every route), [`deployment.md`](https://github.com/TranXuanAnh930/i-dolly-backend/blob/main/docs/deployment.md) |
| Frontend | [`architecture.md`](https://github.com/TranXuanAnh930/i-dolly-frontend/blob/main/docs/architecture.md), [`business_logic.md`](https://github.com/TranXuanAnh930/i-dolly-frontend/blob/main/docs/business_logic.md) |

## License

Proprietary — all rights reserved, matching both submodules.
