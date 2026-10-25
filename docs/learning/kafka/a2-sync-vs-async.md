# A2. How services talk: synchronous vs asynchronous

Decision: [ADR 0002](../../adr/0002-how-the-monolith-talks-to-split-services.md) (events for after-the-fact work, sync query with a 300 ms timeout for the balance)

## The picture (drawn by Claude)

```
 SYNC: call and wait                         ASYNC: send and move on
 Monolith ──POST──▶ Loyalty (down)           Monolith ──OrderPlaced──▶ [broker keeps it] ──▶ Loyalty (later)
 ✗ order fails, or points lost forever       ✓ order succeeds; points arrive when Loyalty is back

 COMMAND: monolith knows everyone            EVENT: nobody is known
 PlaceOrder(): send to Loyalty,              PlaceOrder(): publish OrderPlaced   (never changes)
   Email, Analytics  ← edit per feature        ├─▶ Loyalty    ┐ each subscribes itself,
                                               ├─▶ Email      │ one consumer group each,
                                               └─▶ Analytics  ┘ each with its own bookmark

 Rule: sync when the caller needs the answer to continue; async when it doesn't.
 "Real-time" = fresh within seconds.  "Synchronous" = the caller waits.  Not the same.

 Long timeouts cascade:  Loyalty hangs → 60 s waits pile up → shared pool empty → checkout down
 (SQL Server: "Timeout expired ... prior to obtaining a connection from the pool")

 Bridge: Service Broker = an async queue inside one database (SEND now, RECEIVE later; one reader).
         Kafka topic   = publish/subscribe (every group reads every message).
```

## My five bullets (written by you, in your own words)

1.
2.
3.
4.
5.

## Teach-back
How I'd explain to my team why analytics must not be a synchronous call from checkout:

>
