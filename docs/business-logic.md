# Business logic

[← Back to README](../README.md)

The rules that make this an idol-ticketing platform rather than generic CRUD — enforced at the
database layer (a Postgres trigger, `app/exception/db_triggers.py` in the backend repo translates a
trigger's `RAISE EXCEPTION` back into a clean HTTP error) everywhere money or a scarce seat is at
stake, not just in the API layer, so the invariant holds even against a bug or a direct DB write.
Full detail: [`database-design.md` §4](https://github.com/TranXuanAnh930/i-dolly-backend/blob/main/docs/database-design.md)
(RBAC/fan-only/anti-resale) and §5 (the lottery/checkout trigger-enforced rules, as sequence
diagrams) — 8 trigger functions across the two — plus the frontend's
[`business_logic.md`](https://github.com/TranXuanAnh930/i-dolly-frontend/blob/main/docs/business_logic.md).

- **One ticket per fan per concert, across every sale path.** Bought direct, won a lottery tier, or
  applied to a second tier hoping to trade up — a fan can hold at most one live ticket for a given
  concert at a time. Checked in the service layer first (a clean 400/403), with a DB trigger as the
  backstop if that check is ever bypassed.
- **Lottery fairness: rank order first, one shot per fan, no purchase multiplier.** A fan ranks the
  tiers they'd accept before applying; the draw processes rank 1 across every tier's campaign for a
  concert before moving to rank 2, so no fan can win a lower-ranked tier while a higher-ranked one
  they're still eligible for hasn't been decided yet. Winners within a rank are drawn with
  `secrets.SystemRandom()` (CSPRNG), not `random`'s Mersenne Twister — cryptographically random,
  not just statistically uniform.
- **Anti-resale cap.** A category flagged `is_resale_capped` limits how many units of one product a
  single fan can buy across their order history — enforced by a trigger on `orders_items`, not just
  a cart-side check, so it holds even for a checkout path that skips the normal cart flow.
- **Fan-only purchase actions.** Cart, checkout, lottery entry, and direct ticket purchase all
  reject a manager/admin account outright — staff accounts exist to run the platform, not shop on
  it. A 403 (authorization), not a 400 (validation), since the account and the resource are both
  otherwise perfectly valid.
- **Company-scoped management, not one shared admin pool.** A manager only ever sees and mutates
  their own company's groups/idols/concerts/ticket types/lottery campaigns — enforced by a
  `company_id` filter at the query level on every mutating/manager-facing endpoint, not just hidden
  in the UI. Admins bypass the scope entirely.
- **Payment idempotency as a business guarantee, not just a technical one.** A payment only ever
  transitions out of `pending` once — whether the frontend's own capture call or PayPal's webhook
  gets there first, the second caller always finds a non-pending payment and no-ops, so a retried or
  duplicated request can never double-charge a fan or double-issue a ticket.
