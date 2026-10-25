# ADR 0002: Events for after-the-fact work, synchronous queries with a short timeout for reads

- **Status:** Accepted
- **Date:** 2026-10-26
- **Scope:** eCommerce (on paper; the user's real backend). Kafka curriculum module A2
- **Decided by:** the user
- **Builds on:** [ADR 0001](0001-split-ecommerce-in-steps.md) (Orders, Inventory, Payments stay in the monolith; after-the-fact capabilities split out first)

## Context
Under ADR 0001 the monolith keeps checkout and must now talk to split-out
services: Loyalty, Email, Analytics. In the monolith these were function
calls: instant, never "down". Between services there are two ways to talk:

- **Synchronous** (call and wait): both sides must be up at the same moment
  (temporal coupling). If the callee is down or slow, the caller fails or waits.
- **Asynchronous** (send and move on): a broker stores the message durably
  until the receiver is ready. The receiver catches up later (eventual consistency).

And three kinds of message:
- **Command:** tells a specific service to do something ("AddLoyaltyPoints"). The
  sender knows the receiver, and the receiver may refuse.
- **Event:** states a fact that already happened ("OrderPlaced"). The sender doesn't
  know who listens; new subscribers need no change to the sender.
- **Query:** asks for data and changes nothing ("what is customer 7's balance?").

Rule of thumb adopted: **synchronous when the caller needs the answer to
continue; asynchronous when it doesn't.** And "real-time" (fresh within seconds)
is not the same as "synchronous" (the caller waits).

## Decision

| # | Interaction | Style | Why |
|---|---|---|---|
| 1 | Loyalty: earn points after an order | Async **event** (`OrderPlaced`) | Checkout needs nothing back. If Loyalty is down, points arrive late but are never lost (it catches up) |
| 2 | Order confirmation email | Async **event** (`OrderPlaced`) | Can happen separately; adding it needs no monolith change |
| 3 | Real-time order analytics | Async **event** (`OrderPlaced`) | A few seconds of delay is fine for a dashboard; an analytics outage must never stop checkout |
| 4 | Loyalty balance on the "My orders" page | Sync **query**, **300 ms timeout**, fallback: show the orders with "points unavailable" | The page needs the answer to show it; the page budget is ~1 s, and Loyalty normally answers in tens of ms |

The monolith publishes **one** event, `OrderPlaced`. Loyalty, Email and
Analytics each subscribe on their own (publish/subscribe, one consumer group
each). They are never named in `PlaceOrder`.

## Consequences
- **Good:** checkout depends on none of the split-out services being up. New
  after-the-fact features (e.g. SMS, recommendations) subscribe to `OrderPlaced`
  with no change to the monolith, the riskiest code.
- **Cost (events):** the flow is no longer visible in one place. Nothing in
  `PlaceOrder` says who reacts to an order, so the subscribers must be documented
  (or discoverable from tooling).
- **Cost (eventual consistency):** points, emails and dashboard counts lag the
  order by seconds normally, and by the length of an outage when a subscriber is down.
- **Cost (sync query):** the balance is sometimes missing. Never set a long timeout:
  a hanging Loyalty with a 60 s timeout would tie up the monolith's shared
  workers and connections and take checkout down with it (a cascading failure).
- **New work:** `OrderPlaced` must be published reliably even though saving the
  order and publishing can't be one transaction (module A3: outbox, or B12: CDC).
  The 300 ms call needs a circuit breaker eventually (module B7).

## Alternatives considered
- **Row 3 as a sync command:** rejected. "Real-time" was mistaken for
  "synchronous"; it would have let an analytics outage stop revenue.
- **Row 4 as a local copy kept current by `PointsChanged` events:** the page would
  never lose the balance, but more work and seconds-stale. Kept as the upgrade
  path (it's the pattern the news app builds in slice 2 for author names).
- **Row 4 with a 60 s timeout:** rejected (cascading failure, above).

## Revisit when
- "Points unavailable" shows up often enough that customers notice → move row 4 to the local copy.
- A subscriber needs to *answer* the monolith (e.g. "fraud check: approve or not")
  → that's a command or query, not an event; decide it separately.

## News app counterpart
ingest-svc → articles-svc will be async events (no service waits for the other).
The gateway → service calls stay synchronous, because the client is waiting for the answer.
