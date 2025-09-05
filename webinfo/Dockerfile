# webinfo/Dockerfile
FROM python:3.11-slim

ENV PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# (facultatif mais robuste) certificats + toolchain de base
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates build-essential \
    && rm -rf /var/lib/apt/lists/*

# pip à jour + libs nécessaires
RUN python -m pip install --upgrade pip setuptools wheel && \
    pip install --no-cache-dir \
      "fastapi>=0.112" \
      "uvicorn[standard]>=0.30" \
      "python-a2s>=3.4.0"

WORKDIR /app
COPY app.py /app/app.py

EXPOSE 8080
CMD ["uvicorn","app:app","--host","0.0.0.0","--port","8080"]
