# compose-multienv-deploy

Multi-environment deployment system for Docker/Podman Compose: run **production, staging, and fully isolated per-customer instances side by side on one host**, each with its own env file, network, containers, and volumes.

```
./deploy.sh --env production
./deploy.sh --env staging
./deploy.sh --env customer-acme
```

Extracted from a 14-service production platform I build and operate ([architecture](https://github.com/rahb3rt/platform-architecture)).

## What it does

- **Per-environment isolation** — each `--env` gets its own `.env` file, Compose project, network, and volume namespace; environments never share state
- **One-command deploys** — pulls service repos, pre-builds Next.js apps, generates nginx config, then builds and starts the stack
- **Docker and Podman** — auto-detects the available runtime
- **Selective service deploys** — redeploy a single service without touching the rest
- **Production-shaped staging** — staging runs the same compose file and generated nginx config as production, so configuration drift surfaces before customers see it

## Usage

1. `cp .env.example .env` and fill in your values (one per environment)
2. Point `REPOS_DIR` at the directory containing your service repos
3. `./deploy.sh --env <name>`

The included `docker-compose.yml` shows the shape of the stack this drives (API, web apps, workers, MySQL, MinIO, nginx, health checks, monitoring) — adapt the service list to your platform.
