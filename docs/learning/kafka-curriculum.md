# Kafka curriculum: from monolith + SQL Server to event-driven decisions

The goal is to make and defend architecture decisions with Kafka. Getting
Kafka running comes second. The curriculum is built around four facts about
the learner:

| Starting point | What it means for the curriculum |
|---|---|
| Built and architected strong monoliths | Start from what a monolith gives for free (one transaction, JOINs, in-process calls) and show what is lost when it is split, and what replaces it |
| New to microservices | Teach the microservice ideas Kafka depends on *before* Kafka itself (Phase A) |
| SQL Server background | Every Kafka concept gets its closest SQL Server counterpart, **and where the analogy breaks** |
| New to event-driven architecture | EDA vocabulary and patterns come before Kafka mechanics (Phase A) |

Every concept is anchored three ways, so there is always something familiar to hang it on:

```
                 ┌─────────────────────┐
                 │   Kafka concept     │
                 └──────────┬──────────┘
        ┌───────────────────┼────────────────────┐
        ▼                   ▼                    ▼
 SQL Server analogy    News app (built)     eCommerce backend
 (what you know)       (what you can run)   (what you lead at work)
```

## Why this keeps getting forgotten, and the counter-measures

Kafka is usually taught as a list of mechanics (partitions, offsets, ISR)
with nothing familiar to attach them to, so they fade. This curriculum uses
five habits so the learning sticks:

1. **Anchor, don't memorize.** Each concept is learned through its SQL Server
   analogy, then the news app, then eCommerce. A new idea attached to an old one lasts.
2. **Retrieval first.** Every session opens with a 5-minute recall quiz on earlier
   modules, answered from memory before any re-reading. Spacing: the next
   session, about a week later, about a month later. The quiz tracker is at the bottom.
3. **Write it yourself.** Each module ends with one page in `docs/learning/kafka/`
   (in this repo): Claude draws the diagram, **you** write the 5 bullets in your
   own words. Generating the words beats re-reading them.
4. **Teach it back.** End each module by explaining it as you would to your
   engineering team: "why we would (or would not) put Kafka between checkout and
   inventory". Gaps show up immediately.
5. **Decisions as memory anchors.** Each module ends in an ADR (`docs/adr/`). A
   decision you argued for is remembered far longer than a definition.

Two living reference pages grow across the modules and are the first thing to
open when picking Kafka up again after a break:
- `docs/learning/kafka/sql-server-to-kafka.md`: the mapping table (seeded below)
- `docs/learning/kafka/glossary.md`: every term, one line each, in your words

## How one module runs

```
 recall quiz ─▶ the decision ─▶ options ─▶ trade-offs ─▶ internals ─▶ lab ─▶ you decide ─▶ teach-back
 (5 min,        (a real         (2–4)      (cost,         (only what     (test a   (ADR)       (+ your
  earlier        question:                  failure,       the decision   claim)               one-page
  modules)       news + eCom)               reversibility) needs)                              note)
```

Claude lays out the options and pushes back. You make the call.

## How learning, labs and the news app fit together (decided 2026-10-26)

There is no separate learning app. Each kind of work has its own place:

```
             ┌──────────────────────────────────────────────┐
             │  This curriculum                             │
             │  concepts · SQL Server bridge · decisions    │
             └───────┬──────────────────┬───────────────────┘
                     │ claims to test   │ ADRs
                     ▼                  ▼
  ┌──────────────────────────┐   ┌──────────────────────────────┐   ┌────────────────────────────┐
  │ Labs (throwaway)         │   │ News app (the real system)   │   │ eCommerce (on paper)       │
  │ kafka-lab, 3-broker      │   │ ADRs get implemented here,   │   │ same decisions applied to  │
  │ cluster, small scripts   │   │ with CI, CD, gateway, backups│   │ your order flow, written   │
  │ break things freely      │   │ failure drills (capstone)    │   │ up as ADRs and diagrams    │
  └──────────────────────────┘   └──────────────────────────────┘   └────────────────────────────┘
```

- **News app:** it already has CI, CD, the gateway and backups, so Kafka is the only
  new thing. But news is a forgiving domain (duplicates are harmless, ordering
  barely matters, nothing needs rolling back), so it gets a second, small event flow:
  users-svc publishes user events and articles-svc keeps its own copy of author names.
- **Labs** cover what the news app never needs, e.g. a two-script orders/inventory
  saga with a compensating action. They're scripts, never full services.
- **eCommerce on paper** is where the stakes are real (never charge twice,
  order lifecycle in order) and what you take back to work.

### Learn and build in slices
Never implement a decision before its ADR exists, but use each concept within
days of learning it, so it doesn't fade:

```
Phase A (A1–A4)        → no Kafka build; the A1 lab runs on the news app as it is
B1–B4                  → build slice 1: broker + ingest-svc + articles consumer, happy path
B5–B9                  → build slice 2: DLQ, 2 consumer replicas, retention, author-name events
B10–B13                → build slice 3: hardening, security, end-to-end test in platform CI
B14                    → capstone review on the running system
```

---

## Phase A: Bridges (before Kafka itself)

These four modules close the gap between monolith + SQL Server thinking and
event-driven microservices. Most Kafka confusion comes from skipping them.

### A1. From monolith to services: what breaks when you split
- **Monolith (what you know):** `PlaceOrder` is one SQL Server transaction across
  Orders, OrderLines, Inventory, Payments and Loyalty. It either all commits or all
  rolls back. Reports JOIN anything to anything.
- **Split into services:** each service owns its database. There's no JOIN across
  them, and no single transaction across them.
- **News app:** this is already true. `articles-db` and `users-db` are separate, on
  separate private networks, so "articles with author names" can't be a JOIN.
- **eCommerce:** Orders, Inventory, Payments, Catalog and Customers as services; the
  checkout transaction no longer exists as one unit.
- **Concepts:** bounded context, database per service, the modular monolith (a
  valid choice), why teams split (independent deploys, scaling, ownership), and
  what it costs.
- **Lab:** try to serve "articles with author names" in the news app. The options
  are an HTTP call, a copy of the data kept in sync by events, or putting it back
  together. Each one is a trade-off.
- **Decision → ADR:** for your eCommerce backend, what would you split first, and
  what would you deliberately keep in the monolith?

### A2. How services talk: synchronous vs asynchronous
- **Concepts:** request/response (HTTP) vs messages; **temporal coupling** (if
  Payments is down, can checkout still take the order?); commands ("ReserveStock")
  vs events ("OrderPlaced") vs queries; point-to-point queue vs publish/subscribe.
- **SQL Server bridge:** Service Broker (queues and messages inside the database),
  triggers, and SQL Agent jobs polling a table. You have probably built these.
  They're asynchronous messaging, just inside one database.
- **News app:** today the gateway calls services synchronously. Ingestion will be
  asynchronous: ingest-svc never calls articles-svc.
- **eCommerce:** checkout calls Payments synchronously (the customer is waiting),
  but email, loyalty points, analytics and fraud review can happen after the response.
- **Decision → ADR:** which calls in your checkout must be synchronous, and which can become events?

### A3. Event-driven architecture fundamentals
- **An event is a fact in the past tense** ("OrderPlaced"), and it doesn't change. A command
  is a request that can be refused.
- **Three event styles:** event notification ("order 42 changed, ask me"),
  event-carried state transfer (the event carries the data), event sourcing (the
  events *are* the database).
- **Choreography vs orchestration:** services react to each other's events, or a
  coordinator tells each what to do.
- **Eventual consistency:** the "Thanks, your order is received" page. The stock
  count catches up a moment later.
- **Sagas replace distributed transactions:** instead of ROLLBACK, run a
  *compensating action* (release the stock, refund the payment).
- **The dual-write problem and the outbox pattern:** you can't atomically
  `INSERT` the order **and** publish the event. SQL Server bridge: it's the same
  problem as sending an email from inside a stored procedure. A rollback can't
  un-send it. The outbox writes the event to a table in the *same* transaction.
- **News app:** `articles.ingested` is event-carried state transfer, with choreography.
- **eCommerce:** order flow as a saga: OrderPlaced → StockReserved → PaymentCaptured
  → OrderConfirmed; on PaymentFailed → StockReleased.
- **Lab:** two small scripts, "orders" and "inventory", run a saga on `kafka-lab`:
  place an order, reserve stock, fail the payment, and watch the compensating
  "release stock" event.
- **Decision → ADR:** choreography or orchestration for your order flow, and why.

### A4. The log: the SQL Server idea that unlocks Kafka
SQL Server already has a log at its core: the **transaction log**. Tables are
the *current state*; the log is the *ordered history of every change*. Kafka
takes the log out of the database and makes it a shared, durable, readable
thing in its own right ("the database turned inside out").

Seed of `sql-server-to-kafka.md`:

| SQL Server (you know) | Kafka | Where the analogy breaks |
|---|---|---|
| Transaction log | Topic partition (an append-only log) | You can read Kafka's log directly, keep it for days or forever, and many readers share it |
| LSN (log sequence number) | Offset | Offsets are per partition, not global |
| Transactional replication: Log Reader Agent → distribution DB → subscribers, each at its own position | Producer → topic → consumer groups, each with its own committed offset | Kafka has no "distribution DB"; the topic *is* the shared store, and subscribers can rewind |
| CDC capture tables | A topic of change events | CDC is tied to one DB; a topic is shared across services |
| Retention / cleanup job on CDC or the distribution DB | `retention.ms`, `retention.bytes` | Kafka deletes whole segments, not rows |
| Temporal (history) table, "current row" | Compacted topic: keeps the latest value per key | No query by column; only "latest per key" |
| Table partitioning (partition function on a column) | Partitions chosen by message key | Kafka partitions are for parallelism and ordering, not query pruning |
| Always On AG: primary + secondaries, synchronous commit | Leader + follower replicas, ISR, `acks=all` | Every partition has its own leader, spread across brokers |
| Service Broker queue + activation procedure | Topic + consumer group | A queue removes a message once processed; Kafka keeps it for everyone else |
| Service Broker poison-message handling (queue disabled after 5 rollbacks) | Poison message → DLQ topic | Kafka never stops the topic for you; you design the policy |
| Stored procedure that MERGEs (upsert) | Idempotent consumer | Same idea, and it matters *more*: Kafka redelivers by design |
| What Kafka does **not** have | No SELECT/WHERE, no indexes on values, no UPDATE/DELETE of a record, no JOIN, no transaction spanning Kafka and your DB | |

- **Lab:** `kafka-dump-log` on a partition file next to the idea of `fn_dblog`
  reading SQL Server's transaction log.
- **Teach-back:** "Kafka is a transaction log you can share" in 2 minutes, to your team.

---

## Phase B: Kafka decisions

Each module: the decision, the three anchors, the internals it needs, a lab, and an ADR.

| # | The decision | News app | eCommerce counterpart | SQL Server bridge |
|---|---|---|---|---|
| 1 | Do we need a broker at all? HTTP vs queue vs log vs DB polling/outbox; when Kafka is the wrong choice | ingest-svc → articles-svc | checkout → inventory, email, fraud, analytics | Service Broker, replication, Agent job polling an outbox table |
| 2 | Event and topic design: what is an event, notification vs state transfer, one topic per entity or per event type, ownership, naming | `articles.ingested` | `orders` with OrderPlaced/Paid/Shipped vs one topic per event | Designing a table vs designing a stream of facts (verbs, not nouns) |
| 3 | Ordering and partitioning: which key, how many partitions, hot keys, the one-way door of adding partitions | key = `source_url` | key = `order_id` (lifecycle in order); `sku` for stock; the flash-sale SKU as a hot key | Partition function; "one writer per row" |
| 4 | Delivery guarantees: which loss or duplication is acceptable, and who pays | duplicate article: harmless (upsert) | duplicate PaymentCaptured = charging twice → idempotency keys | `MERGE`, unique constraints, idempotent procs |
| 5 | Durability vs cost: replication factor, `min.insync.replicas`, broker count, KRaft topology | one small VM: one broker | losing an order is not acceptable: 3 brokers, `acks=all` | Always On sync vs async commit; RPO/RTO |
| 6 | Consumer topology and scaling: in the API vs separate container vs separate service; groups; rebalances; slow consumers | `articles-consumer` container | inventory consumers scaling for a sale | Several Agent jobs or readers on one queue |
| 7 | Failure strategy: poison messages, retries, retry topics, DLQ, pausing; effect on ordering | malformed RSS item | order with an unknown SKU → DLQ, ops review | Service Broker poison-message handling |
| 8 | Contracts and evolution: JSON/Avro/Protobuf, Schema Registry, compatibility, expand/contract | `schema_version` | OrderPlaced v2 adds `currency`; older consumers must survive | Changing a table that 40 reports and procs read |
| 9 | Retention and storage: time vs size vs compaction; buffer vs source of truth | 7 days | order events kept for audit; a compacted topic for each product's latest price | Temporal tables, archiving jobs |
| 10 | Build vs buy and operations: self-host vs MSK / Confluent Cloud / Redpanda; monitoring, lag, SLOs | our VM (AWS step) | managed Kafka for a production store | On-prem SQL Server vs Azure SQL: the same decision |
| 11 | Security: plaintext inside a private network vs TLS + SASL + ACLs; PII and PCI in events | internal network only | never put card data in events; customer PII; per-service credentials | Logins, roles, row-level security |
| 12 | Ecosystem: our own producer vs Kafka Connect; Debezium CDC vs outbox; plain consumers vs Kafka Streams | RSS producer we write | **Debezium on SQL Server CDC**: stream changes out of an existing monolith without changing its code | SQL Server CDC itself |
| 13 | Reversibility and migration: one-way vs two-way doors; moving a monolith to events step by step (strangler fig) | changing key or format later | carve notifications out of the SQL Server monolith first, using CDC or an outbox | Moving reports off the primary to a replica |
| 14 | *(after the ingestion build)* Capstone: architecture review of our ingestion design with failure drills, plus a **design exercise for your eCommerce order flow** with ADRs | the running stack | your order flow on paper | |
| 15 | Where to look things up | | | |

### Internals each module pulls in (only as much as the decision needs)
- **2:** record anatomy (key, value, headers, timestamp), topics, partitions, offsets
- **3:** partitioner (murmur2 key hash, sticky for null keys), ordering per partition, skew
- **4:** `acks`, idempotent producer (producer id + sequence), commit timing, transactions and `read_committed`, why exactly-once stops at Kafka
- **5:** leader/follower, ISR, `min.insync.replicas`, unclean leader election, KRaft controller quorum. Lab: 3-broker cluster, kill the leader
- **6:** poll loop, heartbeats, `max.poll.interval.ms`, assignors, cooperative rebalancing, KIP-848, static membership
- **7:** retries and backoff, DLQ headers, pause/resume
- **9:** segments (`.log`, `.index`, `.timeindex`), deletion vs compaction, tombstones, page cache and sequential I/O
- **10:** CLI tools, `listeners` vs `advertised.listeners`, consumer lag, under-replicated partitions, heap and disk sizing
- **11:** TLS, SASL/SCRAM, ACLs

### 15. Where to look things up
- kafka.apache.org docs: the **Design** chapter, the configuration reference, KIPs
- *Designing Data-Intensive Applications* (Kleppmann), chapter 11: the best bridge from databases to logs
- *Kafka: The Definitive Guide* (2nd ed.)
- *Building Event-Driven Microservices* (Bellemare)
- *Fundamentals of Software Architecture* (Richards, Ford): trade-off analysis
- Debezium SQL Server connector docs (for module 12)
- Michael Nygard's ADR template

---

## Progress and recall tracker

| Module | Done | Recall 1 (next session) | Recall 2 (~1 week) | Recall 3 (~1 month) |
|---|---|---|---|---|
| Intro walkthrough (2026-10-26) | ✓ (3 exercises open) | 2026-10-26: Q1–3 missed (watched, didn't run) → re-ask | | |
| A1 | ADR 0001 ✓ (2026-10-26); note + teach-back open | 2026-10-26: mostly right (4th guarantee = one thing to be up) | | |
| A2 | ADR 0002 ✓ (2026-10-26); note + teach-back open | | | |
| A3 | | | | |
| A4 | | | | |
| B1–B4 | | | | |
| → build slice 1 | | | | |
| B5–B9 | | | | |
| → build slice 2 | | | | |
| B10–B13 | | | | |
| → build slice 3 | | | | |
| B14 capstone | | | | |
