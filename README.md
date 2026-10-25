# news-app-platform

System-level repo for the news app: everything that belongs to the app as a
whole rather than to one service. Services never depend on this repo; this
repo depends on them.

## What lives here
| Path | Purpose |
|---|---|
| `CLAUDE.md` | Shared architecture rules, container checklist and roadmap for every service |
| `docker-compose.yml` | Runs the whole app from pinned GHCR images behind the Traefik gateway |
| NGINX gateway | *(planned)* Second gateway option, to benchmark against Traefik |
| Kafka (in `docker-compose.yml`) | *(planned)* Message broker between `ingest-svc` and articles-svc for news from external sources |

## Services
| Service | Repo | Capability | Image |
|---|---|---|---|
| articles-svc | [articles-svc](https://github.com/ankurvapte/articles-svc) | News articles (read-only) | `ghcr.io/ankurvapte/articles-svc` |
| users-svc | [users-svc](https://github.com/ankurvapte/users-svc) | User accounts/profiles (read + write) | `ghcr.io/ankurvapte/users-svc` |

Each service owns its data and is built, tested and pushed by its own repo's CI
(`linux/arm64` images, one tag per commit SHA). They never read each other's
data; cross-service calls go over HTTP.

```
 client ─https─▶ gateway (Traefik, 127.0.0.1:80/443)      ← the only published ports
                  ├─ /api/v1/articles, /api/v1/categories ─▶ articles-svc ─▶ articles-db
                  ├─ /api/v1/users  (GET/HEAD only)       ─▶ users-svc    ─▶ users-db
                  └─ /health/<svc>/{live,ready}           ─▶ that service's /health/*
```

## Run everything (local deploy)
No service repo needs to be cloned: compose pulls the pinned images from GHCR.
```bash
docker compose up -d
docker compose ps
curl -k https://localhost/health/articles/ready
curl -k https://localhost/health/users/ready
curl -k "https://localhost/api/v1/articles?page_size=2"
docker compose down        # add -v to also delete both database volumes
```
- `-k`: locally Traefik serves its self-signed default certificate, so curl and
  browsers warn about it. A trusted local certificate (mkcert) or Let's Encrypt
  on a real server comes later.
- Traefik dashboard (routers, services, middlewares): http://localhost:8088/dashboard/
- All three ports are bound to `127.0.0.1`, so nothing outside this machine can reach them.

## Deploy a new version
1. Push to a service repo; its CI tests, builds and pushes `ghcr.io/ankurvapte/<svc>:<full sha>`.
2. Put that SHA in the `x-<svc>-image` line at the top of `docker-compose.yml`.
3. `docker compose up -d`: only that service (and its migrate job) is recreated.

Roll back by putting the previous SHA back and running `docker compose up -d` again.
Never deploy `:main`; it moves on every push. To try a change before pushing,
run that service's own compose file from its repo (`docker compose up --build`).

## Gateway rules
- HTTP redirects to HTTPS. Requests for any other host than `PUBLIC_HOST`
  (default `localhost`) get Traefik's 404.
- users-svc is read-only from outside: it has no auth yet, so only `GET`/`HEAD`
  are routed, and `POST`/`PATCH` get a 404 from the gateway.
- Health checks go through the gateway as `/health/<svc>/live|ready`, rewritten
  to the service's own `/health/*`.
- Swagger (`/docs`) is not exposed through the gateway; use a service's own compose for it.
- Gateway 404s are Traefik's plain text, not the `{error, message, request_id}` body.
- Access logs are JSON on stdout (`docker compose logs gateway`). `Overhead` is
  the time Traefik itself added, in nanoseconds; useful for the gateway benchmark later.

Notes:
- Stop each service's own compose (`docker compose down` in its folder) first,
  or its host port and containers will clash with names here.
- Each service has its own Postgres container and volume (`news-app_articles-db-data`,
  `news-app_users-db-data`). `docker compose down -v` resets both to the seed data.
- Look inside: `docker compose exec users-db psql -U users -c "SELECT * FROM users"`
  or `docker compose exec articles-db psql -U articles -c "SELECT slug FROM articles"`
- Network isolation: each database sits on its own `internal` network
  (`articles-backend`, `users-backend`) shared only with its service, so no other
  container can resolve or reach it, and databases have no internet access.
  Services and the gateway meet on the `services` network.
- Migrations: `articles-migrate` and `users-migrate` are one-shot jobs that run
  `alembic upgrade head` before their service starts. They show as `Exited (0)`
  in `docker compose ps -a`; that's expected. If one fails, its service doesn't
  start: check `docker compose logs users-migrate`.
- The gateway reads the Docker socket (read-only) to discover containers by their
  `traefik.*` labels. That access is powerful; never publish the dashboard port beyond `127.0.0.1`.

## Claude Code
Claude Code reads `CLAUDE.md` from parent folders, so `~/Projects/CLAUDE.md`
is a symlink to `news-app-platform/CLAUDE.md`. On a fresh machine:
```bash
ln -s news-app-platform/CLAUDE.md ~/Projects/CLAUDE.md
```
