# A1. From monolith to services: what breaks when you split

Decision: [ADR 0001](../../adr/0001-split-ecommerce-in-steps.md) (split in steps, after-the-fact capabilities first)

## The picture (drawn by Claude)

```
 MONOLITH                                           SPLIT
 ┌──────────── one SQL transaction ───────────┐     Orders ─HTTP─ Inventory ─HTTP─ Payments ─HTTP─ Loyalty
 │ INSERT Orders                              │     orders-db    inventory-db    payments-db    loyalty-db
 │ UPDATE Inventory ... WHERE Qty >= @n (lock)│
 │ INSERT Payments                            │     ✗ atomicity    no BEGIN TRAN across databases
 │ UPDATE LoyaltyPoints                       │     ✗ isolation    check-then-decrement can oversell
 │ COMMIT  (all or nothing)                   │     ✗ availability 0.999⁴ ≈ 99.6% (~2.9 h/month down)
 └────────────────────────────────────────────┘     ✗ reads        no JOIN across owners

 Half-done states are not equal:
   stock reserved, not paid  → cheap, expires by itself
   charged, no order         → refunds, chargebacks, trust
 So: order the steps so the likely failure is the cheap one.
   reserve stock (expires) → authorize payment → confirm order → capture payment
```

## My five bullets (written by you, in your own words)

1.
2.
3.
4.
5.

## Teach-back
How I'd explain to my team why we don't split Payments first:

>
