# CLAUDE.md

Shared guidance for every service of the news app. It applies to every folder
under `~/Projects` (Claude Code reads CLAUDE.md from parent directories).
Each service also has its own `CLAUDE.md` with commands and service-specific details.

A news app built to learn containerization and microservice architecture.
Each service: Python 3.12, FastAPI, runs in Docker, has its own git repo.
Each service's `README.md` is its public contract (data model, endpoints, env vars). Keep it in sync when those change.

## Services
| Service | Folder | Capability | Host port (compose) |
|---|---|---|---|
| articles-svc | `articles-svc/` | News articles (read-only) | 8090 |
| users-svc | `users-svc/` | User accounts/profiles (read + write) | 8081 |

`news-app-platform/` holds system-level files: this `CLAUDE.md` (symlinked to
`~/Projects/CLAUDE.md`), a `docker-compose.yml` that runs all services together,
and later the API gateway. Services never depend on it. Add new services to its
compose file and README.

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
- **Docker:** each compose file maps one host port to container port 8080. If that host port is taken, the container gets created without its port binding: free the port, then `docker compose up -d --force-recreate`. Compose `environment:` overrides Dockerfile `ENV`, which overrides `config.py` defaults.
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
- [ ] CI per repo: on every push run tests, build the image, push it to a registry (GHCR) tagged with the commit SHA
- [ ] Deploy to a web server
  - [ ] Platform compose runs pinned registry images (no `build:`); secrets live on the server, never in a repo
  - [ ] Reverse proxy / API gateway (NGINX or Traefik) with TLS as the only public entry; DBs never exposed
  - [ ] Lock down users-svc writes before going public (no auth yet): block or protect them at the gateway
  - [ ] Nightly Postgres backups off the server, and a tested restore
  - [ ] External uptime check on `/health/ready` through the gateway
- [ ] CD: merge to `main` deploys automatically, checks `/health/ready`, one-command rollback to the previous image tag
- [ ] News ingestion from external sources via Kafka (once CD works)
  - [ ] Check server memory first: Kafka wants about 1 GB more RAM; resize the server if needed
  - [ ] Kafka (single KRaft broker, no ZooKeeper) in `news-app-platform` compose; topics `articles.ingested` + `articles.ingested.dlq`
  - [ ] New `ingest-svc`: polls external sources (RSS first, then a news API) on a schedule, normalizes items and publishes them keyed by source URL. Owns no article data.
  - [ ] articles-svc consumer: idempotent upsert into its own Postgres (unique source URL), manual offset commit after the DB write, bad messages go to the DLQ
  - [ ] articles-svc becomes read + ingest: add `source_url`, `published_at`, `ingested_at` to the data model (README contract)
  - [ ] Hardening: per-source retries/backoff and rate limits, consumer lag in `/health/ready` or logs, scale the consumer to 2 replicas in one consumer group
  - [ ] End-to-end test in platform CI (ingest-svc → Kafka → articles-svc), since per-repo CI can't cover the flow
- [ ] Skills for the best practices (anytime, blocks nothing; best written down right after the step that taught the practice)
