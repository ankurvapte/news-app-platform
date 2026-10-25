# CLAUDE.md

Shared guidance for every service of the news app. It applies to every folder
under `~/Projects` (Claude Code reads CLAUDE.md from parent directories).
Each service also has its own `CLAUDE.md` with commands and service-specific details.

A news app built to learn containerization and microservice architecture.
Each service: Python 3.12, FastAPI, runs in Docker, has its own git repo.
Each service's `README.md` is its public contract (data model, endpoints, env vars). Keep it in sync when those change.

## Services
| Service | Folder | Capability | Host port (own compose) | Gateway paths (platform compose) |
|---|---|---|---|---|
| articles-svc | `articles-svc/` | News articles (read-only) | 8090 | `/api/v1/articles`, `/api/v1/categories`, `/health/articles/*` |
| users-svc | `users-svc/` | User accounts/profiles (read + write) | 8081 | `/api/v1/users` (GET/HEAD only), `/health/users/*` |

`news-app-platform/` holds system-level files: this `CLAUDE.md` (symlinked to
`~/Projects/CLAUDE.md`) and a `docker-compose.yml` that runs all services together
from pinned GHCR images behind the Traefik gateway. Services never depend on it.
Add new services to its compose file and README: an `x-<svc>-image` anchor with a
full-SHA tag, `traefik.*` labels for its routes (and `/health/<svc>/*`), no host ports.

Services never read each other's data. A future cross-service call (e.g.
articles → users for author details) goes over HTTP with a timeout and
forwards `X-Request-ID`.

## Architecture rules (always follow)
Clean architecture; dependencies point inward only:
`api → application → domain`, and `infrastructure` implements `application/ports.py`.
- `app/domain/` — entities and business rules. Pure Python. Never import FastAPI, pydantic, json, os or any infrastructure here.
- `app/application/` — use cases (`<Thing>Service`) and ports (interfaces). No HTTP concepts (status codes, Request).
- `app/infrastructure/` — adapters (JSON file or Postgres, picked in `main.py` from env). Only place that knows where data lives.
- `app/api/` — thin HTTP layer: parse input, call a use case, map to `schemas.py`. No business logic.
- `app/main.py` — composition root; the only place layers are wired together.

## How a service fits together
- **Wiring:** `main.py` calls `load_settings()` at import time. Then `lifespan` builds the repository and the service, and stores them (plus `settings`) on `app.state`. Routes get the service via `Depends(get_service)`. `/health/ready` reads `app.state.repository.is_ready()`. A new adapter only needs to satisfy the repository Protocol and be swapped in `lifespan`.
- **Errors:** use cases and domain raise plain exceptions; `main.py` exception handlers map them to HTTP status + the `{error, message, request_id}` body. A new error needs a handler there. Never raise `HTTPException` from lower layers.
- **Pagination:** `page_size` is defaulted and clamped to `MAX_PAGE_SIZE` in `api/routes.py` (from settings). The service's list use case only checks that it's positive.
- **Schema migrations:** Alembic per service in `migrations/versions/` (plain SQL via `op.execute`). A one-shot `<svc>-migrate` compose service (same image, `alembic upgrade head`) runs before the app, which starts only after it exits 0. Repositories never create or alter tables. Never edit a deployed migration; add a new one that keeps the old and new app versions working (expand, then contract).
- **Load failures:** repositories log and report not-ready instead of raising. The container stays up with `/health/ready` → 503 instead of crash-looping. New adapters should follow the same pattern.
- **Request middleware** (`main.py`) reuses or generates `X-Request-ID`, echoes it on the response and logs one JSON line per non-health request. Log extra fields with `logger.info("msg", extra={...})`; `logging_setup.py` turns `extra` keys into top-level JSON keys.
- **Shared code is copied, not shared:** `logging_setup.py`, `api/health.py`, the middleware and Dockerfile are duplicated per service on purpose, so each service can be built and deployed on its own.
- **Tests:** `test_use_cases.py` is plain unittest (no deps) over the real seed data file. `test_api.py` sets `DATA_FILE` before importing `app.main` (settings load on import) and uses `with TestClient(app)` so `lifespan` runs.
- **Gateway (platform compose):** Traefik discovers services by `traefik.*` labels (`exposedbydefault=false`); it is the only container with published ports, bound to `127.0.0.1`. Routes match `Host(${PUBLIC_HOST:-localhost})` + path; write methods on users-svc are not routed. Label `$` must be written `$$` in compose.
- **Docker:** each service's own compose file maps one host port to container port 8080. If that host port is taken, the container gets created without its port binding: free the port, then `docker compose up -d --force-recreate`. Compose `environment:` overrides Dockerfile `ENV`, which overrides `config.py` defaults.
- **Networks (platform compose):** each database joins only its own `internal: true` network (`<svc>-backend`) shared with its service; services meet on `services`. A new service with a DB gets its own backend network; the gateway and Kafka join `services` only, never a backend network.

## Container-first checklist for every change
1. One business capability per service. Users, comments, search etc. are separate services.
2. Stateless: no in-memory or local-disk state that must survive a restart (persistent data goes on a volume or in a database).
3. Config from environment variables only (`app/config.py`); never hardcode, never bake secrets into the image.
4. Own your data: never read another service's database or data files.
5. API is versioned (`/api/v1`) and errors use the `{error, message, request_id}` format.
6. Image stays small and non-root (multi-stage `Dockerfile`, keep `.dockerignore` current).
7. Observability: JSON logs to stdout, propagate `X-Request-ID`, keep `/health/live` and `/health/ready` accurate.
8. Design for failure: timeouts/retries on outbound calls, graceful shutdown in `lifespan`.
9. Add/adjust unit tests for domain and use cases with every change.

## Roadmap (from the Containerization project)
- [x] Best-practice pillars defined
- [x] articles-svc: mock data (10 articles) + read API
- [x] users-svc: CRUD-lite API (JSON file on a named volume)
- [x] users-svc on Postgres + docker-compose DB (database per service)
- [x] articles-svc on Postgres + docker-compose DB (same pattern as users-svc), so every service has its final storage before deploy
- [x] Schema migrations (Alembic) in both services, replacing `schema.sql`; applied by a one-shot migrate container before the app starts
- [x] CI per repo: on every push run tests, build the image, push it to a registry (GHCR) tagged with the commit SHA
  - `.github/workflows/ci.yml`, identical in every service repo, on native ARM runners (`linux/arm64` images): tests (with a Postgres service container) → build → smoke test `/health/ready` → push `ghcr.io/ankurvapte/<svc>:<full sha>` (+ `:main` on main)
  - Decided: images are public (they hold no secrets; the server pulls without a token).
  - Decided: CI does not touch the platform compose. Tags are pinned by hand at the Deploy step; CD automates the bump.
- [ ] Learning session: YAML and GitHub Actions in depth (paused 2026-10-25 by choice; resume when the user asks, walk through it together, don't rush)
  - [x] YAML itself: maps, lists, scalars, indentation, quoting (`"3.12"` vs `3.12`), `|` vs `>-`, comments, anchors (`&`/`*`, used in the platform compose)
  - [ ] GitHub Actions model: workflow → events (`on:`) → jobs → steps; `uses:` vs `run:`; `needs:`, `services:`, `permissions:`, `concurrency:` (explained; its 5 exercises not answered yet, start there)
  - [ ] Expressions and contexts: `${{ }}` vs `$VAR`, the `github` context (using the real values from the "Show github context" step), `steps.<id>.outputs`, secrets
  - [ ] Reading `ci.yml` and `docker-compose.yml` line by line; then write a small workflow from scratch and check it with `actionlint`
  - [ ] Where to look things up: workflow syntax, events and contexts docs, action READMEs/`action.yml`, starter-workflows, VS Code GitHub Actions + YAML extensions
- [ ] Deploy locally (production-like, on this Mac): learn and iterate on deploys without a VM to start or stop (decided 2026-10-25)
  - [x] Platform compose runs pinned registry images (`x-<svc>-image` anchors with full-SHA tags, no `build:`)
  - [x] Traefik gateway (`traefik:v3.7.16`) as the only entry: ports bound to `127.0.0.1`, HTTP → HTTPS, routes by `Host(PUBLIC_HOST)` + path, `/health/<svc>/*` rewritten to each service's `/health/*`; services and DBs publish no ports
  - [x] users-svc writes blocked at the gateway (only GET/HEAD routed)
  - [ ] Trusted local TLS (mkcert) instead of Traefik's self-signed default cert
  - [ ] Postgres backups (`pg_dump` per DB to a folder outside the volumes) and a tested restore
  - [ ] Health check through the gateway on a schedule (a script or a small uptime container hitting `/health/<svc>/ready`)
  - Secrets: dev default passwords are fine locally; real ones go in an untracked `.env` on whatever machine runs it, never in a repo
- [ ] CD (local first): merge to `main` deploys automatically, checks `/health/ready` through the gateway, one-command rollback to the previous image tag
  - Open: how a push reaches this Mac: a self-hosted GitHub Actions runner here, or a pull-based updater that watches GHCR/the platform repo
- [ ] Gateway benchmark: Traefik vs NGINX on the same machine (after CD; locally first)
  - Why both gateways: to benchmark them against each other. Keep the gateway swappable: same services and routes, gateway picked per deploy (e.g. compose profiles), services never depend on which one runs.
  - [ ] NGINX gateway with the same routes, TLS and users-svc write block as Traefik
  - [ ] CD can deploy with either gateway
  - [ ] Fair test: same machine, same image tags, same endpoints, HTTPS on; warm-up run first, several runs each. Locally the load tool (e.g. `k6` or `oha`) shares the Mac's CPU, so compare the two gateways with each other, not with real-server numbers; repeat on AWS later
  - [ ] Compare throughput (req/s), latency p50/p95/p99, error rate, gateway CPU/RAM; also an empty baseline (a static response) to separate gateway cost from app cost
  - [ ] Write up the results
- [ ] Later (parked 2026-10-25): deploy to AWS. Reuses the local setup; only the host, TLS and secrets change
  - Decided (2026-10-25): AWS, one small VM that can be stopped when unused (cost matters); lean and fast deploys. Own domain deferred (user's choice); start on a free hostname (e.g. DuckDNS or sslip.io) with real Let's Encrypt TLS, and keep the hostname in one env var so switching to a bought domain later is a config change. Traefik first; NGINX later as a second gateway option, and CD should be able to deploy with either.
  - Decided: ARM (Graviton `t4g`) instance. CI runs on native ARM runners (`ubuntu-24.04-arm`) and builds `linux/arm64` only (server and dev Macs are both ARM).
  - Decided: access via AWS SSM only (instance role with `AmazonSSMManagedInstanceCore`); no SSH port, no key pairs. Security group inbound: 80/443 only. CD will reach the server through SSM too (GitHub OIDC → AWS role, no long-lived AWS keys).
  - Decided: DuckDNS hostname, region Mumbai (`ap-south-1`), instance size `t4g.small` (2 vCPU / 2 GB; resize the stopped instance to `t4g.medium` when Kafka arrives). Check current prices when this step starts.
  - [ ] Secrets live on the server (untracked `.env`), never in a repo
  - [ ] Traefik with Let's Encrypt TLS for the DuckDNS hostname (`PUBLIC_HOST`); ports 80/443 public instead of `127.0.0.1`
  - [ ] Nightly Postgres backups off the server, and a tested restore
  - [ ] External uptime check on `/health/<svc>/ready` through the gateway
  - [ ] CD deploys to the server through SSM
- [ ] News ingestion from external sources via Kafka (once CD works)
  - [ ] Check memory first: Kafka wants about 1 GB more RAM (Docker Desktop's memory limit locally; the instance size on AWS)
  - [ ] Kafka (single KRaft broker, no ZooKeeper) in `news-app-platform` compose; topics `articles.ingested` + `articles.ingested.dlq`
  - [ ] New `ingest-svc`: polls external sources (RSS first, then a news API) on a schedule, normalizes items and publishes them keyed by source URL. Owns no article data.
  - [ ] articles-svc consumer: idempotent upsert into its own Postgres (unique source URL), manual offset commit after the DB write, bad messages go to the DLQ
  - [ ] articles-svc becomes read + ingest: add `source_url`, `published_at`, `ingested_at` to the data model (README contract)
  - [ ] Hardening: per-source retries/backoff and rate limits, consumer lag in `/health/ready` or logs, scale the consumer to 2 replicas in one consumer group
  - [ ] End-to-end test in platform CI (ingest-svc → Kafka → articles-svc), since per-repo CI can't cover the flow
- [ ] Skills for the best practices (anytime, blocks nothing; best written down right after the step that taught the practice)
