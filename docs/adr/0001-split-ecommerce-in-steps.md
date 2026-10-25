# ADR 0001: Split the eCommerce backend in steps, after-the-fact capabilities first

- **Status:** Accepted
- **Date:** 2026-10-26
- **Scope:** eCommerce (on paper; the user's real backend). Kafka curriculum module A1
- **Decided by:** the user

## Context
`PlaceOrder` today is one SQL Server transaction: insert the order and its lines,
decrement stock (`WHERE Qty >= @n`, row lock), record the payment, add loyalty
points, then `COMMIT`. SQL Server gives four guarantees for free:

| Guarantee | What it protects |
|---|---|
| Atomicity | No order saved without its stock taken; failures roll everything back |
| Isolation | Row lock: two customers can't both buy the last unit |
| One thing to be up | SQL Server up → checkout works |
| One place to read | Confirmation and history pages are one JOIN |

Splitting into services (one database each) loses all four: no transaction or
JOIN across databases, oversell risk if the stock check and decrement are split,
and availability multiplies down (four 99.9% services in a row ≈ 99.6%, about
2.9 h/month of checkout downtime vs ~44 min).

The failures are not equal. "Stock reserved, not paid" is cheap and recovers by
itself (the reservation expires). "Charged, no order" costs the customer's
money and trust (refunds, chargebacks). Payments is where a mistake hurts the
business most. The team has strong monolith and SQL Server experience and is
new to event-driven systems.

## Options
- **A. Big bang.** Split Orders, Inventory, Payments and Loyalty at once.
  Sagas, the outbox pattern and idempotency must all work before go-live, on the
  revenue path, with no experience yet.
- **B. In steps (strangler fig).** Keep Orders, Inventory and Payments together
  in the monolith, inside one transaction. First split the capabilities that
  happen *after* an order or are only *read*, fed by an `OrderPlaced` event.
  Split Inventory, then Payments, later.

## Decision
**Option B.** The service boundaries (Orders, Inventory, Payments, Loyalty) are
the target architecture. They are reached in steps, starting where a mistake
costs a delayed email rather than a double charge.

## Consequences
- **Good:** checkout keeps its SQL transaction and its four guarantees. The team learns
  events, eventual consistency and operating a broker on low-risk flows first.
  Each step is small and reversible.
- **Cost:** the monolith stays the deploy and scaling unit for the core flow for
  now. Two styles run side by side (transaction inside, events outside).
- **New work:** the monolith must publish `OrderPlaced` reliably. Writing the
  order and sending the event can't be one transaction (the dual-write problem),
  so this needs the outbox pattern (module A3) or CDC with Debezium on
  SQL Server (B12).
- **Eventual consistency:** split-out capabilities (e.g. loyalty points, emails)
  show up seconds after the order, not inside the same response.

## Revisit when
- The team has run event-driven flows in production and handled their failures
  (DLQ, redelivery, idempotency).
- The core shows real pain that splitting would fix: deploys of one part
  blocked by another, inventory contention during sales, or one part needing
  to scale alone.

## Open questions
- **Loyalty: earning vs redeeming.** Earning points happens after the order, so it
  is a first-wave candidate. Redeeming points at checkout is payment-like and stays in the
  core. Which does the platform do?
- **What else is "after the fact"?** Candidates: confirmation emails and SMS,
  search, reports and analytics, recommendations, reviews.
- **Payment gateway today:** if the card is charged and then `COMMIT` fails, or
  the gateway call times out, what happens? (Authorize then capture, an
  idempotency key, a reconciliation job?) This is already a two-system
  transaction inside the monolith, and the bridge to sagas in module A3.

## News app counterpart
Articles and users were separate services from day one, because nothing
writes to both in one action. The only break that shows is the read side:
"articles with author names" can't be a JOIN (answered by an event flow in
build slice 2).
