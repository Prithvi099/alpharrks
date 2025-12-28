# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Overview

This repository contains the "Alpha0" platform, built as a small FastAPI-based microservice backend with a static HTML/JS frontend and Docker Compose orchestration. The typical way to run the stack is via Docker (Postgres + Redis + five backend services + gateway + nginx-based frontend).

Key runtime components (see `docker-compose.yml`):
- `postgres`, `redis` infrastructure services
- Backend microservices under `services/` (`auth-service`, `workflow-service`, `ai-service`, `notification-service`, `storage-service`)
- `gateway/` FastAPI API gateway
- `frontend/` static SPA served by nginx, proxying `/api` to the gateway and `/ws` to the notification service

## Common commands

All commands assume the repo root as the working directory unless noted.

### One-command local bring-up (Docker, Windows/PowerShell)

These scripts are the primary local dev entry points on Windows (PowerShell):

- Full clean + rebuild + health check + optional browser open:
  - Interactive (may prompt before pruning):
    - `powershell -ExecutionPolicy Bypass -File .\scripts\run_local.ps1`
  - Force non-interactive clean + rebuild:
    - `powershell -ExecutionPolicy Bypass -File .\scripts\run_local.ps1 -Force`
  - Rebuild without Docker prune:
    - `powershell -ExecutionPolicy Bypass -File .\scripts\run_local.ps1 -Rebuild`

- Build/start, wait for health, request demo token via gateway, open WS listener, optional browser open:
  - `powershell -ExecutionPolicy Bypass -File .\scripts\start_all.ps1 -Rebuild -OpenBrowser`

Notes:
- `start_all.ps1` will create a root `.env` file with example values if it does not exist.
- Health checks hit `http://localhost:8000/health` (gateway) and `http://localhost:3000/` (frontend).

### Direct Docker Compose usage

Helper wrappers:
- From repo root, call the script wrapper around `docker compose`:
  - `powershell -ExecutionPolicy Bypass -File .\dc.ps1 up -d --build`
  - `powershell -ExecutionPolicy Bypass -File .\dc.ps1 logs --tail 200 gateway frontend`
  - `powershell -ExecutionPolicy Bypass -File .\dc.ps1 ps`
- Or call the underlying script directly from within the repo:
  - `powershell -ExecutionPolicy Bypass -File .\scripts\dc.ps1 up -d --build`

Equivalent raw Docker Compose commands (no wrapper):
- `docker compose up -d --build`
- `docker compose logs --tail 200 gateway frontend`
- `docker compose ps`

### Service-level development (without Docker)

Each backend service is a FastAPI app with `app = FastAPI(...)` in `main.py`. To run an individual service directly (e.g., for debugging) you can, from within that service directory, invoke `uvicorn` on the `main:app` app and bind to the same port used in `docker-compose.yml`:

- Auth service (port 8001):
  - `cd services/auth-service`
  - `uvicorn main:app --reload --port 8001`
- Workflow service (port 8002):
  - `cd services/workflow-service`
  - `uvicorn main:app --reload --port 8002`
- AI service (port 8003):
  - `cd services/ai-service`
  - `uvicorn main:app --reload --port 8003`
- Notification service (port 8004):
  - `cd services/notification-service`
  - `uvicorn main:app --reload --port 8004`
- Storage service (port 8005):
  - `cd services/storage-service`
  - `uvicorn main:app --reload --port 8005`
- Gateway (port 8000):
  - `cd gateway`
  - `uvicorn main:app --reload --port 8000`

Python dependencies are per-service via their `requirements.txt` files (e.g. `services/auth-service/requirements.txt`, `services/workflow-service/requirements.txt`, etc.). To develop a single service without Docker:

- (Optional) Create/activate a virtualenv (Python 3.11+ recommended).
- Install dependencies for that service only, e.g.:
  - `pip install -r services/auth-service/requirements.txt`

> Note: several services import `shared.*` modules. Ensure the repo root is on `PYTHONPATH` or install the project as a package if you run services directly outside Docker.

### Tests

There is no `tests/` directory in the repo as checked in, but the GitHub Actions workflow `.github/workflows/deploy.yml` expects Python tests to live under `tests/` and runs them via `pytest`:

- CI test command (from repo root):
  - `pytest tests/ --cov=services`

When tests are added, typical commands will be:
- Run all tests:
  - `pytest`
- Run tests in a single file:
  - `pytest tests/test_some_module.py`
- Run a single test case:
  - `pytest tests/test_some_module.py::TestClass::test_case_name`

### Scripts for Docker cleanup / reinstall (Windows)

- Safe helper to uninstall and optionally reinstall Docker Desktop (see `scripts/README.md` for details):
  - Dry run:
    - `powershell -ExecutionPolicy Bypass -File .\scripts\docker_reinstall.ps1 -DryRun`
  - Cleanup and reinstall then reboot:
    - `powershell -ExecutionPolicy Bypass -File .\scripts\docker_reinstall.ps1 -Reinstall -AutoReboot`

- Deep clean + optional full rebuild of Docker images (can free disk space; see `scripts/clean_rebuild.ps1`):
  - `powershell -ExecutionPolicy Bypass -File .\scripts\clean_rebuild.ps1`

## High-level architecture

### Top-level layout

- `gateway/` – FastAPI API gateway that fronts all backend services and provides a `/health` aggregate endpoint.
- `services/` – Individual FastAPI microservices:
  - `auth-service/`
  - `workflow-service/`
  - `ai-service/`
  - `notification-service/`
  - `storage-service/`
- `frontend/` – Static SPA (HTML/CSS/JS) served by nginx, with reverse-proxy rules to the gateway and notification service.
- `shared/` – Shared Python utilities used across services (SQLAlchemy base model, config, Redis client, etc.).
- `scripts/` – PowerShell helper scripts to manage Docker, clean/rebuild, health checks, etc.
- `documentation/` – Markdown-style documentation file with prerequisites and quick-start hints.
- `examples/` – Example Python client code (e.g. `sample_workflow.py`) demonstrating how to call the gateway and workflow APIs.
- `.github/workflows/` – CI pipeline for running Python tests and building/pushing Docker images.

### Request flow and networking

End-to-end request flow in the typical Docker-based setup:

1. Browser connects to the `frontend` container on port 3000 (mapped from nginx port 80).
2. Nginx inside `frontend` proxies:
   - `/api/*` requests to the `gateway` service (FastAPI app on port 8000 inside Docker).
   - `/ws/*` WebSocket connections to the `notification-service` (FastAPI WebSocket endpoint on `/ws/{user_id}`).
3. The gateway defines a single catch-all route in `gateway/main.py`:
   - `/{service}/{path:path}` with methods `GET, POST, PUT, DELETE, PATCH`.
   - It proxies requests to one of the backend services based on `{service}` using environment variables like `AUTH_SERVICE_URL`, `WORKFLOW_SERVICE_URL`, etc.
4. Backend services may also talk directly to each other over the Docker network:
   - `workflow-service` invokes other services using `httpx.post("http://{task.service}/{task.endpoint}", ...)` where `task.service` matches a Docker service name such as `ai-service` or `storage-service`.
5. All services expose a `/health` endpoint. The gateway aggregates these in its own `/health` route, which the scripts use to determine readiness.

### Services

#### Auth service (`services/auth-service`)

- FastAPI app in `main.py` with a demo `/token` endpoint using `OAuth2PasswordRequestForm`.
- Issues JWT-like access tokens via a function `create_access_token` imported from `shared.auth` (note: the corresponding `shared/auth.py` file is not present in this repo; any work touching auth will likely need to add or restore it).
- SQLAlchemy user model in `models.py` (`User` extends `shared.models.BaseModel`), and a simple DB setup in `database.py` using `DATABASE_URL` (defaults to a Postgres URL when not provided via env vars).
- Intended responsibilities:
  - User management and token issuance.
  - Acts as the source of truth for the `sub` (subject/user ID) claim used by other services.

#### Workflow service (`services/workflow-service`)

- FastAPI app in `main.py` with endpoints to create workflows, list user workflows, start executions, and inspect execution history.
- Uses `verify_token` from `shared.auth` to get `token_data` and derive the current user ID from `token_data["sub"]`.
- Persists workflows using SQLAlchemy models in `models.py`:
  - `Workflow` – top-level workflow definition with `user_id` and status.
  - `Task` – individual steps with fields `service`, `endpoint`, `parameters` (JSON-encoded), and `order`.
  - `WorkflowExecution` – execution records with status, timestamps, result, and error fields.
- DB access uses `database.py` (`DATABASE_URL` configurable via env vars). `Base.metadata.create_all(bind=engine)` is called at startup to create tables.
- Execution model:
  - When `/workflows/{workflow_id}/execute` is called, it creates a `WorkflowExecution` row and schedules `run_workflow` as a FastAPI background task.
  - `run_workflow` obtains its own DB session and iterates over the `Task` rows ordered by `order`:
    - For each task, it constructs an HTTP URL `http://{task.service}/{task.endpoint}` and POSTs `parameters` (after JSON-deserializing the stored string).
    - There is a special placeholder handling for `"{{previous}}"` in `parameters` – if present, it is replaced with the JSON-serialized results of prior tasks.
  - Aggregated step results are stored as JSON in `WorkflowExecution.result`.
- `scheduler.py` currently provides a stub `schedule_workflow(workflow_id, cron)` that only logs. Hook for later true scheduling (APScheduler, Celery Beat, etc.).

#### AI service (`services/ai-service`)

- FastAPI app in `main.py` implementing text analysis and generation endpoints:
  - `/analyze/text` – accepts `TextAnalysisRequest { text, task }` and maps `task` to a pre-defined prompt template (sentiment, summary, keywords). Uses `openai.ChatCompletion.create` with `gpt-3.5-turbo`.
  - `/generate/text` – accepts `TextGenerationRequest { prompt, max_tokens, temperature }` and calls OpenAI ChatCompletion.
  - `/analyze/image` – placeholder for future image analysis (currently returns a static message).
  - `/process/data` – placeholder for structured data processing.
- Auth: all non-health endpoints depend on `verify_token` from `shared.auth`.
- Configuration: uses `OPENAI_API_KEY` from env vars; `docker-compose.yml` passes it through from the root `.env` file.

#### Notification service (`services/notification-service`)

- FastAPI app in `main.py` for email and real-time push notifications.
- Email:
  - `/notify/email` endpoint receives `EmailNotification { to, subject, body, html }` and uses `email_handler.send_email`.
  - `email_handler.py` builds MIME messages and sends via `aiosmtplib` using SMTP settings from env vars (`SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `SMTP_FROM`).
- WebSocket-based push notifications:
  - `/ws/{user_id}` WebSocket endpoint accepts and tracks connections per string `user_id` using `ConnectionManager` in `websocket_manager.py`.
  - `/notify/push` endpoint sends a structured JSON notification to a specific connected user via WebSocket.
  - `/notify/broadcast` endpoint broadcasts a JSON payload to all active WebSocket connections.
- Auth: HTTP endpoints depend on `verify_token`; `user_id` is typically derived from token `sub`, and the frontend uses that same identifier when opening WebSocket connections.

#### Storage service (`services/storage-service`)

- FastAPI app in `main.py` providing a thin wrapper over S3-like storage (via `boto3`).
- Core endpoints:
  - `POST /upload` – uploads a file, using `folder` (default `uploads`) and the authenticated `user_id` (from token `sub`) to build the S3 key `folder/{user_id}/{filename}`; returns `FileMetadata { key, size, content_type, url }` with a presigned URL.
  - `GET /download/{file_key}` – streams a file back to the client.
  - `DELETE /delete/{file_key}` – deletes a file.
  - `GET /list` – lists objects under `folder/{user_id}/`.
- Configuration via env vars (wired in `docker-compose.yml` and `.env`): `AWS_ACCESS_KEY`, `AWS_SECRET_KEY`, `AWS_REGION`, `S3_BUCKET`.

#### Gateway (`gateway`)

- FastAPI app in `main.py` acting as a reverse proxy and health aggregator.
- Service URL mapping is configured via env vars (with Docker service URL defaults):
  - `AUTH_SERVICE_URL`, `WORKFLOW_SERVICE_URL`, `AI_SERVICE_URL`, `NOTIFICATION_SERVICE_URL`, `STORAGE_SERVICE_URL`.
- Main route:
  - `/{service}/{path:path}` forwards method + headers (except `Host`) + body/query params to the corresponding service.
  - Uses `httpx.AsyncClient` and re-emits status code, body, and headers in the response.
- `/health` endpoint iterates through all configured services and calls `GET {service_url}/health` to build a map of `healthy | unhealthy | unreachable`.

#### Frontend (`frontend`)

- Nginx-based static frontend (see `frontend/Dockerfile`). Key pieces:
  - `index.html` and `styles.css` provide the UI.
  - `app.js` implements client-side logic with a simple `Alpha0App` class.
- API integration:
  - Uses a relative base URL of `/api` so that nginx can proxy to the gateway (e.g., `fetch('/api/workflow/workflows')`).
  - WebSockets connect to `/ws/{user_id}` on the same host/port, relying on nginx to proxy to the notification service.
  - JWT token is stored in `localStorage` and decoded client-side to obtain `sub` for WebSocket user ID.
- The frontend is intended to be served via the `frontend` Docker container; there is no Node-based build pipeline here (plain HTML/CSS/JS).

### Shared utilities (`shared`)

- `shared/models.py` – defines the base SQLAlchemy `Base` and `BaseModel` with `id`, `created_at`, `updated_at`. Many service-specific models inherit from this.
- `shared/config.py` – `Settings` class (Pydantic settings) that encapsulates database URL, Redis host/port, secret key, and AWS/S3 defaults; reads from `.env`.
- `shared/redis_client.py` – lightweight JSON-aware Redis wrapper used for key/value operations with automatic JSON serialization and TTL management.
- Several services import `shared.auth` for `create_access_token` and `verify_token`, but that module is missing from the repo. If you see import errors around `shared.auth`, you will need to implement or restore `shared/auth.py` with JWT/authorization helpers consistent with how `token_data["sub"]` is used across services.

### Example clients and documentation

- `examples/sample_workflow.py` demonstrates how an external Python client can:
  - Authenticate via the gateway (`POST /auth/token`) to obtain a bearer token.
  - Use that token to create a workflow via `POST /workflow/workflows`.
  - Define tasks targeting multiple services (AI analysis, storage upload, notification push) with ordered steps and placeholder-like references in `parameters`.
- `documentation/markdown` contains a short Markdown-style doc with high-level prerequisites (Docker, Python 3.11+, Node.js 18+, PostgreSQL 15+, Redis 7+) and an initial "Quick Start" snippet.

## Notes for future Warp agents

- Prefer using the PowerShell helper scripts (`scripts/run_local.ps1`, `scripts/start_all.ps1`, `scripts/dc.ps1`, root `dc.ps1`) when running on Windows, since they encapsulate health checks, `.env` bootstrapping, and diagnostics.
- For cross-platform automation or CI-style flows, interact directly with `docker compose` and the FastAPI apps as described above.
- Be aware of the missing `shared/auth.py` module when working on authentication or when trying to run services outside Docker; adding or fixing this module is likely required before many endpoints will function end-to-end without stubbing auth.
