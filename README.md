# news-app-platform

System-level repo for the news app: everything that belongs to the app as a
whole rather than to one service. Services never depend on this repo; this
repo depends on them.

## What lives here
| Path | Purpose |
|---|---|
| `CLAUDE.md` | Shared architecture rules and container checklist for every service |
| `docker-compose.yml` | Runs all services together |
| `gateway/` | *(planned)* API gateway config (NGINX/Traefik) |
| Kafka (in `docker-compose.yml`) | *(planned)* Message broker between `ingest-svc` and articles-svc for news from external sources |

## Services
| Service | Repo | Capability | Host port |
|---|---|---|---|
| articles-svc | [articles-svc](https://github.com/ankurvapte/articles-svc) | News articles (read-only) | 8090 |
| users-svc | [users-svc](https://github.com/ankurvapte/users-svc) | User accounts/profiles (read + write) | 8081 |

Each service owns its data and is built, tested and deployed from its own repo.
They never read each other's data; cross-service calls go over HTTP.

```
  client ──▶ articles-svc :8090 ──▶ articles-db (Postgres, articles-db-data volume, not exposed)
  client ──▶ users-svc    :8081 ──▶ users-db    (Postgres, users-db-data volume, not exposed)
```

## Run everything
Clone the repos side by side:
```
~/Projects/
├── news-app-platform/   ← this repo
├── articles-svc/
└── users-svc/
```
Then:
```bash
docker compose up --build -d
docker compose ps
curl localhost:8090/health/ready
curl localhost:8081/health/ready
docker compose down        # add -v to also delete both database volumes
```
Swagger UI: http://localhost:8090/docs and http://localhost:8081/docs

Notes:
- Uses the same host ports as each service's own compose file, so stop those
  first (`docker compose down` in the service folder) or the ports will clash.
- Each service has its own Postgres container and volume (`news-app_articles-db-data`,
  `news-app_users-db-data`), separate from the ones created by running a service
  on its own. `docker compose down -v` resets both to the seed data.
- Look inside: `docker compose exec users-db psql -U users -c "SELECT * FROM users"`
  or `docker compose exec articles-db psql -U articles -c "SELECT slug FROM articles"`
- Network isolation: each database sits on its own `internal` network
  (`articles-backend`, `users-backend`) shared only with its service, so no other
  container can resolve or reach it, and databases have no internet access.
  Services talk to each other on the `services` network.
- Migrations: `articles-migrate` and `users-migrate` are one-shot jobs that run
  `alembic upgrade head` before their service starts. They show as `Exited (0)`
  in `docker compose ps -a`; that's expected. If one fails, its service doesn't
  start: check `docker compose logs users-migrate`.

## Claude Code
Claude Code reads `CLAUDE.md` from parent folders, so `~/Projects/CLAUDE.md`
is a symlink to `news-app-platform/CLAUDE.md`. On a fresh machine:
```bash
ln -s news-app-platform/CLAUDE.md ~/Projects/CLAUDE.md
```
