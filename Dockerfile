FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    TASKSPHERE_DB=/data/tasksphere.db

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .
COPY templates templates
COPY static static

RUN mkdir -p /data
EXPOSE 8000

# One worker with threads keeps Prometheus counters accurate; scaling is done by Kubernetes pods.
CMD ["gunicorn", "--workers", "1", "--threads", "4", "--bind", "0.0.0.0:8000", "app:app"]