# Status and roadmap

[← Back to README](../README.md)

## Known limitations

Read each submodule's own current list rather than trusting a summary here — start with
[`i-dolly-backend/README.md#known-limitations`](https://github.com/TranXuanAnh930/i-dolly-backend#known-limitations),
its `docs/project_status.md` and its bug backlog `docs/bugs.md`. In short: this is a portfolio
project, not a system under continuous production traffic — treat it accordingly.

One specific gap worth naming directly rather than leaving buried in that list: **no sweep job for
expired unpaid lottery-won tickets.** A fan who wins and never pays before `payment_deadline_at`
should have that reserved seat released back to the pool — nothing does this on a schedule today.
The deadline is only checked lazily, when the winner tries to pay (`checkout_won_ticket`, or PayPal
payment finalization); a winner who never comes back keeps the seat reserved indefinitely. Full
detail: `i-dolly-backend/docs/project_status.md` §8.

## How it's verified

- **Unit tests** (440+): services tested with mocked sessions and an in-memory fake Redis.
- **Integration tests** (~250): the real HTTP stack against real Postgres and Redis, run on a
  freshly migrated test database — including RBAC and company-scoping checks, and race tests that
  run two transactions at once: concurrent checkouts, concurrent draws, and a lottery apply or
  ranking change racing a draw. The race tests are checked to fail when the lock they rely on is
  removed.
- **CI:** lint plus the full suite on pushes and pull requests to `main` (and `develop`).
- **Live checks** on the deployed domains (certificates, redirects, CORS).

## Open issues

Tracked in the backend's [`docs/bugs.md`](https://github.com/TranXuanAnh930/i-dolly-backend/blob/main/docs/bugs.md),
in priority order:

| Area | Issue | Status |
|---|---|---|
| Security | IP-based rate limits can be bypassed with a forged `X-Forwarded-For` (#7) | Fix planned (`docs/plans/rate-limit-client-ip.md`) |
| Data integrity | Deleting a product removes its lines from past orders (#2) | Open |
| Orders | Cancelling an order doesn't restock or refund (#14); cancelled orders still count toward the resale cap (#13) | Open |
| Payments | PayPal capture runs while row locks are held, and a capture that succeeded but didn't commit isn't reconciled (#8) | Needs design |
| Payments | Abandoned PayPal checkouts stay `pending` with no expiry: a direct-sale ticket blocks the fan from buying again (#12), orders clutter history (#27), and unpaid orders can be marked shipped (#26) | Deferred, to be fixed together |
| Resilience | If Redis is down, cached pages return 500 (#11) | Needs design |
| Auth | Changing a password doesn't end other sessions; reset links are reusable until they expire; refresh tokens are stored in plain text (#18–#20) | Open |

Recently fixed: duplicate shipping-status rows per order, deleting another user's cart items,
lottery applications outside the entry window, ranking changes that broke the draw, a fan winning
twice in one tier, route handlers blocking the event loop, `DEBUG` defaulting to on, cart price
drift, confirmation emails sent before the commit, and PayPal webhook events that crashed the
handler.

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
- **Scheduled clean-up jobs** — expire unpaid lottery wins and abandoned PayPal checkouts on a
  schedule (Celery Beat), instead of relying on the lazy checks described above.
- **Event reminders** — remind ticket holders before their concert. The `event_reminder`
  notification type already exists in the backend, but nothing sends it yet; it needs a scheduled
  job that finds upcoming concerts and notifies each fan holding a paid ticket, in-app and possibly
  by email. How far ahead to remind, and on which channels, is still undecided.
- **Contact (お問い合わせ) emails on the project domain** — a contact form whose inquiries reach an
  address on `i-dolly-app.site` (for example `support@i-dolly-app.site`). Cloudflare Email Routing
  can receive and forward mail for the domain but can't send it, so incoming inquiries would be
  forwarded to an inbox, and any automatic acknowledgement to the sender would go out through
  Resend, like the app's other emails. The address, form fields and spam protection are still
  undecided.
