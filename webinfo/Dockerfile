FROM python:3.11-slim

WORKDIR /app
# FastAPI + Uvicorn + A2S (le bon paquet est "python-a2s")
RUN pip install --no-cache-dir fastapi uvicorn && \
    pip uninstall -y a2s || true && \
    pip install --no-cache-dir "python-a2s>=3.4.0"

COPY app.py /app/app.py

EXPOSE 8080
CMD ["uvicorn","app:app","--host","0.0.0.0","--port","8080"]
