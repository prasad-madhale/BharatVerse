# BharatVerse

Discover India's epic past, one story at a time! BharatVerse delivers daily, AI-curated historical tales from India's vibrant history—perfect for a quick, enriching read every day!

## 🏗️ Project Structure (Monorepo)

This is a monorepo containing three main services:

```
BharatVerse/
├── scrapper/          # Content pipeline (Python)
├── backend/           # REST API (FastAPI)
├── bharatverse_app/   # Mobile app (Flutter)
└── docs/              # Documentation
```

## 🚀 Quick Start

### Prerequisites

- **Python 3.12+** (required - see [Python Setup](#python-setup) below)
- **Flutter SDK 3.x** (for mobile app)
- **Node.js 18+** (optional, for tooling)

### Python Setup

This project requires Python 3.12 or higher. Here's how to install it:

#### macOS (using Homebrew)

```bash
# Install Python 3.12
brew install python@3.12

# Verify installation
python3.12 --version

# Set as default (optional)
brew link python@3.12
```

#### macOS (using pyenv - Recommended)

```bash
# Install pyenv
brew install pyenv

# Add to shell profile (~/.zshrc or ~/.bash_profile)
echo 'export PYENV_ROOT="$HOME/.pyenv"' >> ~/.zshrc
echo 'export PATH="$PYENV_ROOT/bin:$PATH"' >> ~/.zshrc
echo 'eval "$(pyenv init -)"' >> ~/.zshrc
source ~/.zshrc

# Install Python 3.12
pyenv install 3.12.0
pyenv global 3.12.0

# Verify
python --version  # Should show Python 3.12.0
```

#### Ubuntu/Debian

```bash
# Add deadsnakes PPA
sudo add-apt-repository ppa:deadsnakes/ppa
sudo apt update

# Install Python 3.12
sudo apt install python3.12 python3.12-venv python3.12-dev

# Verify
python3.12 --version
```

#### Windows

Download and install from [python.org](https://www.python.org/downloads/) (version 3.12+)

### 1. Clone Repository

```bash
git clone <repository-url>
cd BharatVerse
```

### 2. Set Up Environment Variables

Create a `.env` file in the project root:

```bash
cp .env.example .env
# Edit .env and add your API keys
```

Required environment variables:
- `GEMINI_API_KEY` - For article generation (FREE - get from https://makersuite.google.com/app/apikey)
  - Alternative: `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, or `GROQ_API_KEY`
- `LLM_PROVIDER` - Which LLM to use: `gemini` (default), `anthropic`, `openai`, or `groq`
- `JWT_SECRET_KEY` - For authentication (generate with `openssl rand -hex 32`)
- `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` - For Google OAuth (optional)
- `FACEBOOK_APP_ID`, `FACEBOOK_APP_SECRET` - For Facebook OAuth (optional)

### 3. Build Each Service

#### Content Pipeline (scrapper)

```bash
# Ensure you're using Python 3.12+
python3 --version  # Should be 3.12.0 or higher

# Create virtual environment with Python 3.12
python3.12 -m venv .venv
# OR if using pyenv: python -m venv .venv

source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Verify Python version in venv
python --version  # Should show 3.12+

# Install dependencies
pip install -r scrapper/requirements.txt

# Install browser binaries for Playwright
playwright install

# Run scrapper
python scrapper/scrapper_main.py
```

See [scrapper/README.md](scrapper/README.md) for detailed instructions.

#### Backend API

```bash
# Activate virtual environment (if not already active)
source .venv/bin/activate

# Install dependencies
pip install -r backend/requirements.txt

# Initialize database
python backend/init_db.py

# Run API server
uvicorn backend.main:app --reload --host 0.0.0.0 --port 8000
```

See [backend/README.md](backend/README.md) for detailed instructions.

#### Mobile App (Flutter)

```bash
cd bharatverse_app

# Get dependencies
flutter pub get

# Run on connected device/emulator
flutter run

# Run tests
flutter test
```

See [bharatverse_app/README.md](bharatverse_app/README.md) for detailed instructions.

## 📚 Documentation

- **[BRD](docs/BharatVerse%20MVP%20BRD.md)** - Business Requirements Document
- **[Requirements](/.kiro/specs/bharatverse-mvp/requirements.md)** - Technical requirements
- **[Design](/.kiro/specs/bharatverse-mvp/design.md)** - System design and architecture
- **[Tasks](/.kiro/specs/bharatverse-mvp/tasks.md)** - Implementation task list
- **[AGENTS.md](/.kiro/AGENTS.md)** - Guide for AI agents working on this codebase

## 🏛️ Architecture Overview

### Content Pipeline (scrapper)
- Scrapes historical content from Wikipedia and archive.org
- Uses Anthropic Claude to generate curated 10-15 minute read articles
- Validates article quality and stores in database

### Backend API (FastAPI)
- REST API for mobile app
- SQLite database with FTS5 full-text search
- User authentication (email/password + OAuth)
- Article search with autocomplete and semantic similarity
- Article likes and user management

### Mobile App (Flutter)
- Cross-platform iOS and Android app
- Daily article feed with offline caching
- Search with autocomplete
- User authentication and article likes
- Markdown rendering for articles

## 🧪 Testing

### Backend Tests
```bash
# Activate virtual environment
source .venv/bin/activate

# Run all tests
pytest

# Run with coverage
pytest --cov=backend --cov=scrapper

# Run property-based tests only
pytest -m property_test
```

### Mobile Tests
```bash
cd bharatverse_app
flutter test
```

## 🚢 Deployment

### Backend Deployment
```bash
# Build Docker image
docker build -t bharatverse-backend .

# Run with docker-compose
docker-compose up -d
```

### Mobile App Release
```bash
# Android
cd bharatverse_app
flutter build apk --release

# iOS
flutter build ios --release
```

See individual service READMEs for detailed deployment instructions.

## 🛠️ Development Workflow

1. **Create feature branch**: `git checkout -b feature/your-feature`
2. **Make changes** and write tests
3. **Run tests**: `pytest` (backend) or `flutter test` (mobile)
4. **Commit changes**: `git commit -m "feat: your feature"`
5. **Push and create PR**: `git push origin feature/your-feature`

## 📝 Tech Stack

- **Backend**: Python 3.12, FastAPI, SQLite, Anthropic Claude
- **Mobile**: Flutter 3.x, Dart
- **Scraping**: Playwright, LangChain
- **Authentication**: JWT, OAuth (Google, Facebook)
- **Testing**: pytest, hypothesis (property-based), flutter_test

## 🤝 Contributing

1. Read the [AGENTS.md](/.kiro/AGENTS.md) guide
2. Check the [tasks.md](/.kiro/specs/bharatverse-mvp/tasks.md) for open tasks
3. Follow the development workflow above
4. Write tests for all new features
5. Update documentation as needed

## 📄 License

See [LICENSE](LICENSE) file for details.

## 🔗 Links

- **API Documentation**: http://localhost:8000/docs (when backend is running)
- **Design Document**: [.kiro/specs/bharatverse-mvp/design.md](/.kiro/specs/bharatverse-mvp/design.md)
- **BRD**: [docs/BharatVerse MVP BRD.md](docs/BharatVerse%20MVP%20BRD.md)
