# Cloud Run image for the EarthSync backend (team code + app endpoints).
# Runtime deps only; versions pinned by requirements.lock (tested resolution).
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /srv
COPY requirements.lock pyproject.toml ./
COPY earthsync ./earthsync
RUN pip install -c requirements.lock . \
    && useradd --create-home --uid 10001 app

USER app
# Cloud Run sets $PORT. Bind all interfaces inside the container only.
CMD ["sh", "-c", "exec uvicorn earthsync.api:app --host 0.0.0.0 --port ${PORT:-8080} --proxy-headers --forwarded-allow-ips='*'"]
