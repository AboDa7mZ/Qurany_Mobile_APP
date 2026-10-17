# 📖 Qurany — Quran Learning & Recitation App

> **A Flutter mobile app powered by an AI backend for Quranic Arabic speech recognition, word-by-word recitation feedback, Tajweed heuristics, and memorization tracking.**

---

## ✨ Features

| Feature | Description |
|---------|-------------|
| 📜 **Mushaf Reader** | Full Quran reader with authentic Arabic typography (MeQuran font) |
| 🎙️ **Recitation Practice** | Record your recitation and get word-by-word AI feedback |
| 🧠 **Tajweed Heuristics** | Automatic detection of Madd, Ghunnah, Waqf, and Qalqalah rules |
| 📊 **Error Analysis** | Detailed breakdown of substitution, omission, addition & sequence errors |
| 📅 **Khatmah Planner** | Set a reading goal and track daily Quran completion progress |
| 🔔 **Smart Reminders** | Local notifications for scheduled recitation sessions |
| 🔐 **Auth + Guest Mode** | JWT-based accounts with full offline/guest fallback |
| 🔄 **Offline-first Sync** | Local SQLite + server sync with conflict resolution |

---

## 🏗️ Architecture

```
Qurany_Mobile_APP/
├── flutter_app/          # Flutter mobile app (Android / iOS)
├── backend/              # Python FastAPI recitation analysis API
├── Documents/            # Project documentation, diagrams & reports
│   └── diagrams/         # UML: Use Case, Class, ERD, Sequence, Component, Security
├── docs/                 # Workflow diagrams and technical notes
├── ai_prototype/         # Early AI prototype experiments
└── codemagic.yaml        # CI/CD pipeline (Codemagic)
```

### AI Recitation Pipeline

```
Audio (WAV/MP3)
    │
    ▼
ASR — faster-whisper (Tarteel CT2) or fine-tuned Transformers (Hafs + Bazzi)
    │
    ▼
Arabic Normalization (strip tashkeel, unify alef/hamza)
    │
    ▼
Word Alignment — Needleman–Wunsch algorithm
    │
    ▼
Error Classification (substitution / omission / addition / sequence)
    │
    ▼
Tajweed Heuristics (Madd / Ghunnah / Waqf / Qalqalah)
    │
    ▼
Word-by-word feedback + similarity score
```

---

## 🚀 Quick Start

### Flutter App

**Prerequisites:** Flutter SDK, Android Studio, Android SDK (API 34+), NDK 30

```bash
cd flutter_app
flutter pub get
flutter run
```

To connect to the backend:
```bash
flutter run --dart-define=QURANY_API_BASE=http://10.0.2.2:8000
```

> See [`flutter_app/README.md`](flutter_app/README.md) for the full Windows setup guide (Android Studio, SDK, emulator).

---

### Backend (FastAPI)

**Prerequisites:** Python 3.11–3.14, ffmpeg installed on the host

```bash
cd backend
python -m venv .venv
.venv\Scripts\activate          # Windows
# source .venv/bin/activate     # macOS / Linux

pip install -r requirements.txt
copy .env.example .env          # configure your settings

python main.py
# API docs available at http://localhost:8000/docs
```

> See [`backend/README.md`](backend/README.md) for the full API reference, ASR model setup, and fine-tuned model usage.

---

## 🔌 API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/health` | Service & ASR status |
| GET | `/api/v1/surahs` | List supported surahs |
| GET | `/api/v1/surahs/{n}` | Reference text (Uthmani) |
| POST | `/api/v1/analyze` | Audio → full recitation feedback |
| POST | `/api/v1/analyze-text` | Transcript → comparison feedback |
| POST | `/api/v1/transcribe` | Audio → transcript only |
| WS | `/api/v1/stream` | Live alignment from chunks |
| POST | `/api/v1/auth/register` | Create account + JWT |
| POST | `/api/v1/auth/login` | Login + JWT |
| GET | `/api/v1/auth/me` | Current user profile |

---

## 🗄️ Database Schema

The backend uses **SQLite** (local dev) / **PostgreSQL** (production) with the following core tables:

| Table | Purpose |
|-------|---------|
| `users` | Authentication, profile, streak & score |
| `recitation_sessions` | Per-session recitation results & scores |
| `recitation_errors` | Word-level error breakdown per session |
| `bookmarks` | Page & ayah bookmarks with notes |
| `khatmah_plans` | Quran completion reading plans |
| `learning_plans` | Memorization & revision plans |
| `schedules` | Notification & reminder schedules |

---

## 📦 Tech Stack

### Flutter App
| Package | Purpose |
|---------|---------|
| `provider` | State management |
| `audioplayers` / `record` | Audio playback & recording |
| `speech_to_text` | On-device Arabic ASR (fallback) |
| `flutter_local_notifications` | Scheduled reminders |
| `flutter_svg` | SVG rendering |
| `google_fonts` | Typography |
| `shared_preferences` | Local persistence |

### Backend
| Technology | Purpose |
|------------|---------|
| **FastAPI** | REST + WebSocket API framework |
| **faster-whisper** | Quranic Arabic ASR (Tarteel CT2 model) |
| **Transformers + PyTorch** | Fine-tuned Whisper (Hafs & Bazzi riwayat) |
| **SQLAlchemy + SQLite** | Local database & ORM |
| **pytest** | 31-test suite (no ASR required) |

---

## 🧪 Testing

```bash
# Backend tests (runs offline — no ASR model required)
cd backend
pytest
```

---

## 📄 Documentation

| Document | Description |
|----------|-------------|
| [`Documents/Qurany_Final_Documentation_Complete.md`](Documents/Qurany_Final_Documentation_Complete.md) | Full project documentation |
| [`Documents/diagrams/`](Documents/diagrams/) | UML diagrams (Use Case, Class, ERD, Sequence, Component, Security) |
| [`implementation_plan.md`](implementation_plan.md) | Database schema & implementation plan |
| [`backend/README.md`](backend/README.md) | Backend API & pipeline details |
| [`flutter_app/README.md`](flutter_app/README.md) | Flutter setup & run guide |

---

## 🎓 Academic Context

This project was developed as a **Faculty of Computer & Information Sciences — Cairo University** graduation project by:

- 20226142 · 20226143 · 20226054 · 20226116 · 20226009

---

## 📝 License

This project is for academic and educational use.
