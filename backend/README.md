# Qurany Backend

Python **FastAPI** backend for the Qurany Quranic recitation learning app.

It receives recitation audio from the Flutter client, transcribes it with
**faster-whisper** (Tarteel CT2 model) or **fine-tuned transformers**
checkpoints (Hafs + Bazzi — see `training/kaggle/`), normalizes the Arabic,
aligns it against the canonical reference text, and returns **word-by-word
feedback** plus best-effort **Tajweed heuristics** (Madd, Ghunnah, Waqf, Qalqalah).

> **MVP scope:** **Surah Al-Naba (78)** and **Surah Al-Baqarah (2)** — the
> latter is the target of the Kaggle fine-tunes (Hafs 'an 'Asim and Al-Bazzi
> 'an Ibn Kathir) in `training/kaggle/`.

## Pipeline

```
audio (wav/mp3...) ──▶ ASR (faster-whisper or ──▶ Arabic normalization ──▶ alignment ──▶ Tajweed
                         fine-tuned transformers)    (strip tashkeel,        (Needleman–     heuristics
                         + word-level timestamps     unify alef/hamza...)    Wunsch)         (Madd/Ghunnah/
                                                                                 │            Waqf/Qalqalah)
                                                                                 ▼
                                          word-by-word errors + similarity score + tajweed notes
```

Error types match the Flutter client (`RecitationError`):
`substitution`, `omission`, `addition`, `sequence`.

Tajweed notes (`madd` | `ghunnah` | `waqf` | `qalqalah`) are **approximate,
explainable heuristics** built on top of ASR word timestamps — not a trained
Tajweed classifier. See `services/tajweed_heuristics.py` for the documented
limitations. Toggle with `ENABLE_TAJWEED_HEURISTICS=false`.

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
│   │   ├── asr_service.py      # faster-whisper / transformers backend (lazy singleton)
│   │   ├── reference_service.py# loads/caches surah reference text (any supported surah)
│   │   ├── alignment_service.py# word alignment + error classification + word_timeline
│   │   ├── tajweed_heuristics.py# Madd/Ghunnah/Waqf/Qalqalah heuristics
│   │   └── analysis_service.py # orchestrates the full pipeline
│   └── utils/
│       └── arabic.py           # normalization + similarity
├── data/surah_naba/surah_naba.json   # seeded Al-Naba reference (Uthmani)
├── data/surah_cache/                 # auto-cached reference text for other surahs (e.g. 2)
├── data/uploads/recitations/         # uploaded audio (transient)
├── models/                     # extracted fine-tuned checkpoints (see training/kaggle/)
├── training/kaggle/            # Kaggle fine-tuning scripts + notebooks (Hafs + Bazzi riwayat) + READMEs
├── data/qurany.db              # SQLite database (auth users; auto-created on startup)
├── tests/                      # pytest suite
└── main.py                     # `python main.py` runner
```

## Getting started

> **Python:** 3.11–3.14 supported; 3.12 recommended for ML wheels.
> **ffmpeg** must be installed on the host for audio decoding.

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

To use the Kaggle fine-tuned model instead of general-purpose faster-whisper:

```bash
# .env
ASR_BACKEND=transformers
CUSTOM_MODEL_PATH=./models/qurany-whisper-base-al-baqarah   # or a HF repo id
```

This requires the optional `transformers` + `torch` (+ `librosa` for the
Qalqalah heuristic) packages — see the commented-out block at the bottom of
`requirements.txt`.

## API

| Method | Path                     | Description                                   |
|--------|--------------------------|-----------------------------------------------|
| GET    | `/health`                | Service + ASR status                          |
| GET    | `/api/v1/surahs`         | Supported surahs (`[78, 2]`)                  |
| GET    | `/api/v1/surahs/{n}`     | Reference text (Uthmani + normalized + ayahs) |
| POST   | `/api/v1/transcribe`     | Audio → transcript only                       |
| POST   | `/api/v1/analyze`        | Audio → transcript + comparison + tajweed feedback |
| POST   | `/api/v1/analyze-text`   | Existing transcript → comparison feedback     |
| WS     | `/api/v1/stream`         | Live alignment from transcript chunks         |
| POST   | `/api/v1/auth/register`  | Create account + JWT                          |
| POST   | `/api/v1/auth/login`     | OAuth2 password login (username=email) + JWT  |
| GET    | `/api/v1/auth/me`        | Current user profile (Bearer token)           |

### Database

Local dev uses **SQLite** (`data/qurany.db`). SQLAlchemy creates tables on
startup via `init_db()`. Override with `DATABASE_URL` in `.env` if needed.

| Variable | Default | Description |
|----------|---------|-------------|
| `DATABASE_URL` | `sqlite:///…/data/qurany.db` | SQLAlchemy database URL |
| `JWT_SECRET` | `change-me-in-production` | JWT signing secret |

### `POST /api/v1/analyze`  (multipart/form-data)

- `file`: recitation audio (wav 16kHz mono, as recorded by the app; mp3/m4a/etc. also accepted)
- `surah_number`: chapter number (default `78`; `2` uses the Al-Baqarah fine-tune if configured)

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
  "segments": [ { "start": 0.0, "end": 2.1, "text": "..." } ],
  "tajweedNotes": [
    { "type": "madd", "expectedWord": "آمَنُوا", "wordIndex": 12, "message": "...", "severity": "warning" }
  ]
}
```

`tajweedNotes` is only populated when word-level timestamps are available
(faster-whisper's `word_timestamps=True`) and `ENABLE_TAJWEED_HEURISTICS=true`
(default); it's always `[]` for `/analyze-text` since there's no audio timing.

`/api/v1/analyze-text` accepts JSON `{ "surah_number": 78, "transcribed_text": "..." }`
and is handy for testing the comparison logic without audio.

## Testing

```bash
pytest                # 31 tests: arabic normalization, alignment, tajweed heuristics, API
```

The test suite does **not** require the ASR model (it exercises the comparison
path via `/analyze-text`), so it runs fast and offline.

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

### Auth

- Register/login call `/api/v1/auth/*` when the backend is reachable.
- JWT is stored locally; guest mode remains offline-only.
- User accounts are stored in the local SQLite database (`data/qurany.db`).

> Note: running the recorder and the platform speech recognizer at the same
> time can contend for the microphone on some devices; if WAV capture fails,
> the app silently uses the on-device transcript instead.
