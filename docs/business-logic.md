# Business logic

[← Back to README](../README.md)

The rules that make this an idol-ticketing platform rather than generic CRUD. Each rule is checked
in the service layer first, which returns a clean 400/403/404. Where money or a scarce seat is at
stake, a Postgres trigger enforces the same rule again as a backstop, so it holds even against a
bug or a direct database write; `app/exception/db_triggers.py` in the backend translates a
trigger's `RAISE EXCEPTION` into the same kind of HTTP error. Rules without a trigger are marked
*service only* below.

Full detail: [`database-design.md` §4](https://github.com/TranXuanAnh930/i-dolly-backend/blob/main/docs/database-design.md)
(RBAC, fan-only, anti-resale) and §5 (lottery and checkout, as sequence diagrams), plus the
frontend's [`business_logic.md`](https://github.com/TranXuanAnh930/i-dolly-frontend/blob/main/docs/business_logic.md).

## Rules and where they're enforced

8 trigger functions, attached as 12 triggers:

| Rule | Database backstop | HTTP error |
|---|---|---|
| Only fans can use the cart, check out, apply to a lottery or own a ticket | `fn_enforce_fan_only_purchase` on `cart`, `orders`, `lottery_entries`, `tickets` | 403 |
| At most one live ticket per fan per concert | `fn_enforce_one_ticket_per_concert` on `tickets` | 400 |
| A concert's ticket tiers can't add up to more than its capacity | `fn_enforce_concert_ticket_capacity` on `ticket_types` | 400 |
| At most 3 units of a resale-capped product per fan, across all their orders | `fn_enforce_resale_cap` on `orders_items` | 400 |
| At most `max_entries_per_user` entries per fan per lottery campaign (fixed at 1) | `fn_enforce_lottery_entry_cap` on `lottery_entries` | 400 |
| A fan must rank a tier before applying to its lottery | `fn_require_lottery_preference` on `lottery_entries` | 400 |
| A ranked tier must belong to the ranked concert | `fn_require_ticket_type_matches_concert` on `lottery_preferences` | 400 |
| A product has album details or merch details, never both | `fn_enforce_single_product_detail_kind` on `album_details`, `merch_details` | 400 |
| One ticket type per (concert, tier, sale method); one payment per idempotency key | UNIQUE constraints, translated the same way | 400 / 409 |

*Service only* (no trigger):

- Lottery applications are accepted only while the campaign is `open` and inside its entry window.
- A fan's tier ranking can only be set while the ranked tiers' campaigns are open, can't change
  once entries close or the draw has run, and can't drop a tier the fan has already applied to.
- Direct-sale tickets can only be bought while a direct-sale campaign for the tier is open and
  inside its sale window, and not while the fan has a pending or won lottery entry for the concert.
- A lottery win must be paid before `payment_deadline_at` (48 hours by default); a late payment
  attempt expires the ticket and releases the seat.
- Managers can't change a product's or ticket type's price after creation (admins can).
- Once a concert is on sale, sold out or completed, managers can't change its date, doors-open
  time or capacity, or resize its ticket tiers; cancelling the concert unlocks them.
- Groups, idols and concerts are deactivated or cancelled rather than deleted, so ticket, order and
  lottery history keeps its references.

## The rules in more detail

- **One ticket per fan per concert, across every sale path.** Bought direct, won a lottery tier, or
  applied to a second tier hoping to trade up — a fan can hold at most one live ticket (reserved,
  pending payment, paid or used) for a given concert at a time. A fan who already holds one can't
  apply to that concert's lotteries either.
- **Lottery fairness: rank order first, one shot per fan, no purchase multiplier.** A fan ranks the
  tiers they'd accept before applying; the draw processes rank 1 across every tier's campaign for a
  concert before moving to rank 2, so no fan can win a lower-ranked tier while a higher-ranked one
  they're still eligible for hasn't been decided yet. Winners within a rank are drawn with
  `secrets.SystemRandom()` (CSPRNG), not `random`'s Mersenne Twister — cryptographically random,
  not just statistically uniform. See [Lottery](#lottery) below.
- **Anti-resale cap.** A category flagged `is_resale_capped` (the default) limits how many units of
  one product a single fan can buy across their order history to 3 — enforced by a trigger on
  `orders_items`, not just a cart-side check, so it holds even for a checkout path that skips the
  normal cart flow.
- **Fan-only purchase actions.** Cart, checkout, lottery entry, and direct ticket purchase all
  reject a manager/admin account outright — staff accounts exist to run the platform, not shop on
  it. A 403 (authorization), not a 400 (validation), since the account and the resource are both
  otherwise perfectly valid.
- **Company-scoped management, not one shared admin pool.** A manager only ever sees and mutates
  their own company's groups/idols/concerts/ticket types/lottery campaigns/products/orders —
  enforced by a `company_id` filter at the query level on every mutating and manager-facing
  endpoint, not just hidden in the UI. A product's company is resolved through its album or merch
  details; products with neither are manageable by any manager. Admins bypass the scope entirely.
- **Payment idempotency as a business guarantee, not just a technical one.** Every checkout carries
  a client-generated idempotency key, so a retried request can't create a second payment. After
  that, a payment only ever transitions out of `pending` once — whether the frontend's own capture
  call or PayPal's webhook gets there first, the second caller finds a non-pending payment and
  no-ops, so a retried or duplicated request can never double-charge a fan or double-issue a
  ticket.

## Lottery

1. **Rank.** The fan submits their full ranked list of the concert's lottery tiers
   (`POST /lottery_preferences/set`); each tier needs a campaign whose entry window has started.
2. **Apply.** During the entry window the fan applies to one or more of the ranked tiers — free, no
   payment. `/lottery_entries/apply-batch` applies to several tiers all-or-nothing, using one
   rate-limit slot.
3. **Draw.** After every campaign's window has closed, a manager of the concert's company triggers
   the draw, which runs in the Celery worker:
   - For rank 1, then rank 2, and so on: for each tier that still has seats, take the pending
     entries at that rank from fans who haven't won yet, and randomly pick as many as there are
     seats left.
   - Each winner gets a `pending_payment` ticket (the seat is counted in `sold_quantity`
     immediately) with a deadline of `payment_deadline_hours` after the draw.
   - Every remaining entry becomes `lost`; every campaign becomes `drawn`.
   - Fans get a `lottery_result` notification per entry, and winners a `lottery_payment_reminder`.
4. **Pay.** The winner pays through `POST /tickets/{ticket_id}/checkout` before the deadline.

Applying and changing a ranking both take a share lock on the campaign rows, and the draw takes an
exclusive lock on them. An apply or ranking change that arrives mid-draw therefore waits, then sees
the campaign as `drawn` and is rejected, instead of adding an entry or preference the draw never
saw. Integration tests race the two against a real Postgres to prove it.

## State machines

| Entity | States |
|---|---|
| Concert | `scheduled` → `on_sale` → `sold_out` / `completed`; `cancelled` at any point |
| Lottery campaign | `open` → `drawn` → `completed`; or `cancelled` |
| Lottery entry | `pending` → `won` / `lost` |
| Ticket | `pending_payment` → `paid` → `used`; `cancelled` (declined direct-sale payment) or `expired` (unpaid lottery win); `reserved` for tickets an admin issues manually |
| Order | `pending` (PayPal awaiting capture) → `confirmed`; or `cancelled` |
| Payment | `pending` → `success` / `failed` |
| Shipping | `pending` → `processing` → `shipped` → `delivered`; or `cancelled` |
