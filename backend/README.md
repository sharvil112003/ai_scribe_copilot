# MediNote Mock Backend (TypeScript)

A lightweight **mock API** that mirrors the endpoints your Flutter app expects. It’s built with **Express + TypeScript**, stores data **in memory**, saves uploaded audio **to disk**, and ships with **Docker** for one-command runs on any machine.

---

## ✨ What you get

* **Ready-made endpoints** for Patients, Templates, Sessions, Presigned URLs, and Chunked Uploads
* **Auth guard** (simple): accepts `Authorization: Bearer demo_*` or a JWT-looking token (`eyJ...`)
* **In-memory DB** (resets on restart) + **uploads/** folder persisted via Docker volume
* **CORS** enabled (`*` by default)
* **Works with or without Docker** (Node 20+ recommended)

---

## 📁 Project Structure

```
backend/
├─ src/
│  └─ server.ts              # main Express server
├─ uploads/                  # saved audio chunks (persisted via volume)
│  └─ .gitkeep
├─ .env.example              # sample env vars
├─ .gitignore
├─ .dockerignore
├─ package.json
├─ tsconfig.json
├─ Dockerfile                # multi-stage build (Node 20)
├─ docker-compose.yml        # one-command up
└─ README.md
```

---

## 🚀 Quick Start

### Option A — Local (no Docker)

```bash
# 1) Install deps (generates package-lock.json)
npm install

# 2) Dev mode (hot reload, no build step)
npm run dev
# Server: http://localhost:3001

# OR: build & run
npx tsc -p tsconfig.json
node dist/server.js
```

### Option B — Docker (recommended for consistency)

```bash
# Build & run in background
docker compose up --build -d

# Tail logs
docker compose logs -f
```

* Health: `http://localhost:3001/health`
* Docs: `http://localhost:3001/api/docs`

> If your network blocks Docker Hub, the Dockerfile uses a **Google mirror** base (`mirror.gcr.io/library/node:20-bookworm-slim`).
> If needed, add DNS in `docker-compose.yml`:
>
> ```yaml
> services:
>   medinote-api:
>     dns: [8.8.8.8, 1.1.1.1]
> ```

---

## ⚙️ Environment

Copy `.env.example` to `.env` (optional):

```env
NODE_ENV=development
PORT=3001
CORS_ORIGIN=*
```

The defaults work out of the box.

---

## 🔐 Authentication

Every app endpoint (except `/health` and `/api/docs`) expects:

```
Authorization: Bearer demo_token_123
```

Accepted formats:

* Any token starting with `demo_` (e.g., `demo_token_123`)
* Any JWT-like token starting with `eyJ...`

---

## 🧪 Smoke Tests

```bash
# Health
curl http://localhost:3001/health

# Docs
curl http://localhost:3001/api/docs

# Patients
curl -H "Authorization: Bearer demo_token_123" \
  "http://localhost:3001/api/v1/patients?userId=user_123"

# Create patient
curl -X POST http://localhost:3001/api/v1/add-patient-ext \
  -H "Authorization: Bearer demo_token_123" -H "Content-Type: application/json" \
  -d '{"name":"Test Patient","userId":"user_123"}'

# Patient details
curl -H "Authorization: Bearer demo_token_123" \
  http://localhost:3001/api/v1/patient-details/patient_123
```

---

## 🎤 Chunked Upload Flow (End-to-End)

1. **Create/Use a session** (returns `id`):

```bash
curl -X POST http://localhost:3001/api/v1/upload-session \
  -H "Authorization: Bearer demo_token_123" -H "Content-Type: application/json" \
  -d '{"patientId":"patient_123","userId":"user_123","patientName":"Alice Johnson"}'
```

2. **Get presigned URL** for a chunk:

```bash
curl -X POST http://localhost:3001/api/v1/get-presigned-url \
  -H "Authorization: Bearer demo_token_123" -H "Content-Type: application/json" \
  -d '{"sessionId":"session_123","chunkNumber":1,"mimeType":"audio/wav"}'
```

3. **PUT the binary** to the presigned URL (mock uploads to local disk):

```bash
curl -X PUT "http://localhost:3001/api/upload-chunk/session_123/1" \
  --data-binary @sample.wav -H "Content-Type: audio/wav"
```

4. **Notify** backend that chunk is uploaded:

```bash
curl -X POST http://localhost:3001/api/v1/notify-chunk-uploaded \
  -H "Authorization: Bearer demo_token_123" -H "Content-Type: application/json" \
  -d '{"sessionId":"session_123","chunkNumber":1,"isLast":true}'
```

* Uploaded files are stored under `uploads/` (persisted via Docker volume).
* When `isLast: true`, the session transitions to `processing` → `completed` with a mock transcript.

---

## 📚 API Reference (Brief)

### System

* `GET /health` → `{ status, timestamp, version }`
* `GET /api/docs` → API summary JSON

### Patient Management

* `GET /api/v1/patients?userId=...`
  → `{ patients: [{id,name}] }`
* `GET /api/users/asd3fd2faec?email=...`
  → `{ id }` or `404`
* `POST /api/v1/add-patient-ext` (`{ name, userId }`)
  → `201 { patient }`
* `GET /api/v1/patient-details/:patientId`
  → `{ ...patient }` or `404`
* `GET /api/v1/fetch-session-by-patient/:patientId`
  → `{ sessions: [...] }`
* `GET /api/v1/all-session?userId=...`
  → `{ sessions: [...], patientMap: {...} }`

### Template Management

* `GET /api/v1/fetch-default-template-ext?userId=...`
  → `{ success: true, data: [{id,title,type}] }`

### Recording / Upload

* `POST /api/v1/upload-session`
  → `201 { id }`
* `POST /api/v1/get-presigned-url` (`{ sessionId, chunkNumber, mimeType }`)
  → `{ url, gcsPath, publicUrl }`
* `PUT /api/upload-chunk/:sessionId/:chunkNumber` (binary)
  → `200` (saves to `uploads/`)
* `POST /api/v1/notify-chunk-uploaded`
  → `{}` (updates session; if `isLast: true`, completes later)

### Debug

* `GET /api/debug/all-data` → counts of entities
* `GET /api/debug/chunks/:sessionId` → chunk metadata

> All non-system endpoints require `Authorization: Bearer <token>`.

---

## 🧱 Implementation Notes

* **In-memory state** for users/patients/templates/sessions; resets on restart.
* **Uploads** are stored under `uploads/` (mounted in Docker to persist).
* **CORS** is open (`*`), configurable via `CORS_ORIGIN`.
* **Error handling**:

  * Missing params → `400`
  * Not found → `404`
  * Uncaught errors → `500 { error, details }`

---

## 🐳 Docker Details

**Dockerfile** (multi-stage):

* Build stage installs dev deps and compiles TS → `dist/`
* Runtime stage installs only prod deps → smaller final image

**docker-compose.yml**:

* Maps `3001:3001`
* Mounts `./uploads` into `/app/uploads`
* `restart: unless-stopped`

Run:

```bash
docker compose up --build -d
docker compose logs -f
```

Stop & remove:

```bash
docker compose down
```

---

