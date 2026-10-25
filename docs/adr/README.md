# Architecture Decision Records

One file per decision: `NNNN-short-title.md`. Most come from the Kafka
curriculum (`docs/learning/kafka-curriculum.md`). **Scope** says whether the
decision is for the news app (built here) or eCommerce (on paper, for the
user's real backend). An ADR is never edited after it's accepted. A new ADR replaces it
and the old one's status becomes "Superseded by NNNN".

| # | Decision | Scope | Status |
|---|---|---|---|
| [0001](0001-split-ecommerce-in-steps.md) | Split the eCommerce backend in steps, after-the-fact capabilities first | eCommerce | Accepted (2026-10-26) |
| [0002](0002-how-the-monolith-talks-to-split-services.md) | Events for after-the-fact work, synchronous queries with a short timeout for reads | eCommerce | Accepted (2026-10-26) |

## Template
```markdown
# ADR NNNN: <decision as a short sentence>
- **Status:** Proposed | Accepted | Superseded by NNNN
- **Date:** YYYY-MM-DD
- **Scope:** news app | eCommerce. Curriculum module <id>
- **Decided by:** <who>

## Context        (the forces: what's true, what hurts, what matters)
## Options        (2–4, each with its main cost)
## Decision       (the choice, and the one-line why)
## Consequences   (good, cost, new work)
## Revisit when   (signals that would reopen it)
## Open questions
```
