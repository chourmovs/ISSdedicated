FROM python:3.11-slim

WORKDIR /app
# libs minimalistes pour FastAPI + A2S
RUN pip install --no-cache-dir fastapi uvicorn a2s

COPY app.py /app/app.py

EXPOSE 8080
CMD ["uvicorn","app:app","--host","0.0.0.0","--port","8080"]
