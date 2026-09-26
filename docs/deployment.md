# Deployment

[← Back to README](../README.md)

- **Backend**: Render (API + a Background Worker for Celery), Supabase (Postgres), an
  S3-compatible bucket (image uploads), Render's Key Value add-on (Redis) — see
  `i-dolly-backend/docs/deployment.md`.
- **Frontend**: Vercel — `vercel.json` rewrites every route to `index.html` for client-side
  routing; the deployed API URL is supplied at build time via `VITE_API_URL`.
- **Domains**: `i-dolly-app.site` (Cloudflare Registrar/DNS). The frontend is served on
  `i-dolly-app.site` and the API on `api.i-dolly-app.site`, both through DNS-only Cloudflare records
  pointing at Vercel and Render. Keeping the API on a subdomain of the same site makes the login
  refresh cookie first-party. Setup, env vars and checks:
  [`deployment.md` §12](https://github.com/TranXuanAnh930/i-dolly-backend/blob/main/docs/deployment.md).
- **Email**: Resend, sending from a verified domain (`mail.i-dolly-app.site`, on Cloudflare
  Registrar/DNS — DKIM, SPF-related CNAMEs, DMARC) rather than Resend's sandbox sender, so
  verification/reset emails deliver to any recipient, not just the account owner.
