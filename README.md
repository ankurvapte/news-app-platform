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

## Services
| Service | Repo | Capability | Host port |
|---|---|---|---|
| articles-svc | [articles-svc](https://github.com/ankurvapte/articles-svc) | News articles (read-only) | 8090 |
| users-svc | [users-svc](https://github.com/ankurvapte/users-svc) | User accounts/profiles (read + write) | 8081 |

Each service owns its data and is built, tested and deployed from its own repo.
They never read each other's data; cross-service calls go over HTTP.

```
  client ──▶ articles-svc :8090   (news.json baked into the image)
  client ──▶ users-svc    :8081   (users.json on the users-data volume)
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
docker compose down        # add -v to also delete the users-data volume
```
Swagger UI: http://localhost:8090/docs and http://localhost:8081/docs

Notes:
- Uses the same host ports as each service's own compose file, so stop those
  first (`docker compose down` in the service folder) or the ports will clash.
- This stack has its own `news-app_users-data` volume, separate from the one
  created by running `users-svc` on its own.

## Claude Code
Claude Code reads `CLAUDE.md` from parent folders, so `~/Projects/CLAUDE.md`
is a symlink to `news-app-platform/CLAUDE.md`. On a fresh machine:
```bash
ln -s news-app-platform/CLAUDE.md ~/Projects/CLAUDE.md
```
