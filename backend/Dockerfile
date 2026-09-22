# Backend API image. Build from the repo root, since backend imports common/ as a sibling package:
#   docker build -f backend/Dockerfile -t bharatverse-backend .
#   docker run --rm -p 8000:8000 --env-file .env bharatverse-backend
FROM python:3.12-slim

WORKDIR /app

COPY backend/requirements.txt backend/requirements.txt
RUN pip install --no-cache-dir -r backend/requirements.txt

COPY common/ common/
COPY backend/ backend/

EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=3s CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health')"

CMD ["uvicorn", "backend.main:app", "--host", "0.0.0.0", "--port", "8000"]
