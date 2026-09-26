# Deployment

[← Back to README](../README.md)

Step-by-step setup, the full environment-variable list and post-deploy checks live in the backend's
[`deployment.md`](https://github.com/TranXuanAnh930/i-dolly-backend/blob/main/docs/deployment.md);
this page is the map.

## What runs where

| Component | Platform | Address / plan |
|---|---|---|
| Frontend (Vue SPA) | Vercel | `https://i-dolly-app.site` (`www.` redirects to it) |
| API (FastAPI) | Render web service, Docker | `https://api.i-dolly-app.site` (docs at `/docs`) · free plan |
| Celery worker | Render background worker, same Docker image | starter plan (Render has no free workers) |
| Redis | Render Key Value | free plan · cache, rate limits, Celery broker |
| PostgreSQL | Supabase | session pooler connection |
| Images | S3-compatible bucket | `STORAGE_BACKEND=s3` |
| Email | Resend | sends from `mail.i-dolly-app.site` |
| DNS and domain | Cloudflare Registrar and DNS | `i-dolly-app.site` |
| Payments | PayPal | sandbox mode |

- **Backend**: the Docker image runs `alembic upgrade head` before starting uvicorn, so every
  deploy applies pending migrations first. The worker runs the same image with a Celery command
  and needs the same database, Redis and email settings as the API. See
  `i-dolly-backend/docs/deployment.md`.
- **Frontend**: Vercel — `vercel.json` rewrites every route to `index.html` for client-side
  routing; the deployed API URL is supplied at build time via `VITE_API_URL`, so changing it needs
  a redeploy.
- **Domains**: `i-dolly-app.site` (Cloudflare Registrar/DNS). The frontend is served on
  `i-dolly-app.site` and the API on `api.i-dolly-app.site`, both through DNS-only Cloudflare records
  pointing at Vercel and Render. Keeping the API on a subdomain of the same site makes the login
  refresh cookie first-party. Setup, env vars and checks:
  [`deployment.md` §12](https://github.com/TranXuanAnh930/i-dolly-backend/blob/main/docs/deployment.md).
- **Email**: Resend, sending from a verified domain (`mail.i-dolly-app.site`, on Cloudflare
  Registrar/DNS — DKIM, SPF-related CNAMEs, DMARC) rather than Resend's sandbox sender, so
  verification/reset emails deliver to any recipient, not just the account owner.

## DNS records

All web records are **DNS only** (grey cloud): Vercel and Render issue their own certificates.

| Name | Type | Points to |
|---|---|---|
| `i-dolly-app.site` | A | Vercel |
| `www` | CNAME | Vercel (redirects to the apex) |
| `api` | CNAME | `i-dolly-backend.onrender.com` |
| `mail` subdomain records | TXT / CNAME | Resend (DKIM, SPF, DMARC) |

## Settings that tie the pieces together

| Where | Setting | Value |
|---|---|---|
| Render (API + worker) | `BASE_URL` | `https://api.i-dolly-app.site` — used in email-verification links |
| Render (API + worker) | `FRONTEND_BASE_URL` | `https://i-dolly-app.site` — used in reset links and PayPal return/cancel URLs |
| Render (API + worker) | `CORS_ORIGINS` | the apex, `www` and the old `vercel.app` address |
| Render (API + worker) | `FROM_EMAIL` | `noreply@mail.i-dolly-app.site` |
| Render (API + worker) | `DEBUG` | unset or `false`, so emails are sent rather than printed to the logs |
| Vercel | `VITE_API_URL` | `https://api.i-dolly-app.site` |
| PayPal dashboard | Webhook URL | the API's `/payment/paypal/webhook`; its id goes in `PAYPAL_WEBHOOK_ID` |

## CI/CD

- **Backend:** GitHub Actions runs `ruff` and the full pytest suite (with Postgres and Redis
  service containers, coverage uploaded to Codecov) on pushes and pull requests to `main`. After
  both pass on `main`, it calls Render's deploy hook if the `RENDER_DEPLOY_HOOK` secret is set.
  Render is also configured to redeploy on every commit to `main`.
- **Frontend:** no CI workflow of its own; Vercel builds and deploys through its Git
  integration.

## Things to know

- Render's free web service sleeps after 15 minutes without traffic, so the first request after
  that can take 30–60 seconds.
- The platform addresses (`i-dolly-frontend.vercel.app`, `i-dolly-backend.onrender.com`) keep
  working alongside the custom domains.
