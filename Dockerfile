# Root Dockerfile - builds the backend service
FROM python:3.12-slim

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Install dependencies
RUN pip install --no-cache-dir -U pip setuptools wheel

# Copy backend code
COPY backend/ /app/backend/

# Install backend package
RUN pip install --no-cache-dir /app/backend

# Create data directory for sqlite spool
RUN mkdir -p /data
ENV SYNQC_JOB_QUEUE_DB_PATH=/data/jobs.sqlite3

EXPOSE 8001

# Run uvicorn
CMD ["uvicorn", "synqc_backend.api:app", "--host", "0.0.0.0", "--port", "8001"]
