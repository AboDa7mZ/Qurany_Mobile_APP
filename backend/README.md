# Qurany Backend

Python **FastAPI** backend for the Qurany Quranic recitation learning app.

It receives recitation audio from the Flutter client, transcribes it with
**faster-whisper** using the Tarteel Quranic Arabic model
([tarteel-ai/whisper-base-ar-quran](https://huggingface.co/tarteel-ai/whisper-base-ar-quran),
loaded via the CT2 build `OdyAsh/faster-whisper-base-ar-quran`), normalizes the
Arabic, aligns it against the canonical Uthmani text, and returns **word-by-word
feedback**.

> **MVP scope:** only **Surah Al-Naba (chapter 78)**.

## Pipeline

```
audio (wav/mp3...) ──▶ faster-whisper ──▶ Arabic normalization ──▶ alignment
                         (transcript)        (strip tashkeel,        (Needleman–
                                              unify alef/hamza...)     Wunsch)
                                                                          │
                                                                          ▼
                                          word-by-word errors + similarity score
```

Error types match the Flutter client (`RecitationError`):
`substitution`, `omission`, `addition`, `sequence`.

## Project structure

```
backend/
├── src/
│   ├── main.py                 # FastAPI app factory (app = create_app())
│   ├── config.py               # Settings (pydantic-settings, .env)
│   ├── api/
│   │   ├── routes.py           # HTTP routes
│   │   └── schemas.py          # Pydantic request/response models
│   ├── services/
│   │   ├── asr_service.py      # faster-whisper wrapper (lazy singleton)
│   │   ├── reference_service.py# loads/caches Surah Al-Naba text
│   │   ├── alignment_service.py# word alignment + error classification
│   │   └── analysis_service.py # orchestrates the full pipeline
│   └── utils/
│       └── arabic.py           # normalization + similarity
├── data/surah_naba/surah_naba.json   # seeded Al-Naba reference (Uthmani)
├── data/uploads/recitations/         # uploaded audio (transient)
├── docker/                     # Dockerfile + docker-compose
├── tests/                      # pytest suite
└── main.py                     # `python main.py` runner
```

## Getting started

> **Python:** developed/verified on 3.14, but 3.11–3.12 are recommended for the
> broadest ML-wheel compatibility. The Docker image uses 3.12.
> **ffmpeg** must be installed for audio decoding (bundled in the Docker image).

```bash
# From backend/
python -m venv .venv
.venv\Scripts\activate          # Windows
# source .venv/bin/activate       # macOS / Linux

pip install -r requirements.txt
copy .env.example .env           # Windows  (cp on macOS/Linux)

python main.py                   # or: uvicorn src.main:app --reload
```

Open the interactive API docs at `http://localhost:8000/docs`.

The first request that needs ASR downloads the Whisper model (cached
afterwards). Default model: `OdyAsh/faster-whisper-base-ar-quran` (CT2 build of
[tarteel-ai/whisper-base-ar-quran](https://huggingface.co/tarteel-ai/whisper-base-ar-quran)).
Override with `WHISPER_MODEL` / `WHISPER_COMPUTE_TYPE`.

### Quick ASR smoke test

```bash
python scripts/download_and_test_tarteel_whisper.py
python scripts/download_and_test_tarteel_whisper.py --audio path/to/recitation.wav
```

## API

| Method | Path                     | Description                                   |
|--------|--------------------------|-----------------------------------------------|
| GET    | `/health`                | Service + ASR status                          |
| GET    | `/api/v1/surahs`         | Supported surahs (`[78]`)                     |
| GET    | `/api/v1/surahs/{n}`     | Reference text (Uthmani + normalized + ayahs) |
| POST   | `/api/v1/transcribe`     | Audio → transcript only                       |
| POST   | `/api/v1/analyze`        | Audio → transcript + comparison feedback      |
| POST   | `/api/v1/analyze-text`   | Existing transcript → comparison feedback     |
| WS     | `/api/v1/stream`         | Live alignment from transcript chunks         |
| POST   | `/api/v1/auth/register`  | Create account + JWT                          |
| POST   | `/api/v1/auth/login`     | OAuth2 password login (username=email) + JWT  |
| GET    | `/api/v1/auth/me`        | Current user profile (Bearer token)           |
| POST   | `/api/v1/sync/push`      | Upload offline-first pending changes          |
| GET    | `/api/v1/sync/pull`      | Download server changes (`updated_after`)   |

### `POST /api/v1/analyze`  (multipart/form-data)

- `file`: recitation audio (wav 16kHz mono, as recorded by the app; mp3/m4a/etc. also accepted)
- `surah_number`: chapter number (default `78`)

**Response** (matches the Flutter `recitation_session` contract):

```json
{
  "transcribed_text": "...",
  "reference_text": "...",
  "similarity_score": 87.5,
  "total_words": 178,
  "matched_words": 156,
  "mistakes": 22,
  "errors": [
    { "type": "substitution", "expectedWord": "النبإ", "recitedWord": "الكتاب", "wordIndex": 3 }
  ],
  "segments": [ { "start": 0.0, "end": 2.1, "text": "..." } ]
}
```

`/api/v1/analyze-text` accepts JSON `{ "surah_number": 78, "transcribed_text": "..." }`
and is handy for testing the comparison logic without audio.

## Testing

```bash
pytest                # 19 tests: arabic normalization, alignment, API
```

The test suite does **not** require the ASR model (it exercises the comparison
path via `/analyze-text`), so it runs fast and offline.

## Docker

```bash
# From backend/ — starts PostgreSQL + API
docker compose -f docker/docker-compose.yml up --build
```

Environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `DATABASE_URL` | SQLite file in `data/qurany.db` | PostgreSQL URL for FastAPI (`postgresql+psycopg://...`) |
| `PRISMA_DATABASE_URL` | — | Standard Postgres URL for Prisma Studio (`postgresql://...`) |
| `JWT_SECRET` | `change-me-in-production` | JWT signing secret |

## Prisma Studio (view tables)

Prisma is configured for **browsing** the PostgreSQL schema in Prisma Studio.  
The FastAPI app still creates/updates tables via SQLAlchemy (`init_db` on startup).

```bash
# 1. Start PostgreSQL + backend (creates tables)
docker compose -f docker/docker-compose.yml up -d postgres backend

# 2. From backend/
copy .env.example .env          # Windows (set DATABASE_URL + PRISMA_DATABASE_URL)
npm install
npm run studio                  # opens http://localhost:5555
```

Useful commands:

```bash
npm run validate    # check schema.prisma
npm run db:pull     # introspect DB after SQLAlchemy schema changes
npm run db:generate # generate Prisma Client (optional)
```

Prisma uses `PRISMA_DATABASE_URL` (standard form):
`postgresql://qurany:qurany@localhost:5432/qurany`  
FastAPI uses `DATABASE_URL` with the SQLAlchemy driver prefix:
`postgresql+psycopg://qurany:qurany@localhost:5432/qurany`

## Flutter integration

Wired up in the app:

- `flutter_app/lib/services/recitation_api_service.dart` — `RecitationApiService`
  (multipart `analyze`, `analyze-text`, `health`), registered as a `Provider`
  in `main.dart`.
- `recitation_screen.dart` records a WAV in parallel with the on-device
  speech recognizer; on stop (free / memorization modes for Surah Al-Naba) it
  POSTs the WAV to `/api/v1/analyze` and uses the result. If the backend is
  unreachable or returns nothing, it **falls back to the on-device**
  `_performLocalComparison` path automatically.

Point the app at your backend with:

```bash
flutter run --dart-define=QURANY_API_BASE=http://10.0.2.2:8000   # Android emulator
```

### Auth & sync

- Register/login call `/api/v1/auth/*` when the backend is reachable.
- JWT is stored locally; guest mode remains offline-only.
- Pending local changes sync via `/api/v1/sync/push` then `/api/v1/sync/pull`.
- Manual sync is available under **Settings → مزامنة البيانات**.

> Note: running the recorder and the platform speech recognizer at the same
> time can contend for the microphone on some devices; if WAV capture fails,
> the app silently uses the on-device transcript instead.
