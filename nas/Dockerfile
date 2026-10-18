FROM python:3.12-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
RUN apt-get update \
    && apt-get install --no-install-recommends -y ffmpeg libheif-examples ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY nas/requirements.txt /app/nas/requirements.txt
RUN pip install --no-cache-dir -r /app/nas/requirements.txt
COPY photographic_style_port.py /app/
COPY nas/server.py nas/live_worker.py /app/nas/
COPY nas/static/ /app/nas/static/
RUN useradd --system --uid 10001 --home /nonexistent --shell /usr/sbin/nologin appuser
USER 10001:10001
EXPOSE 8080
CMD ["uvicorn", "nas.server:app", "--host", "0.0.0.0", "--port", "8080", "--workers", "1", "--no-access-log"]
