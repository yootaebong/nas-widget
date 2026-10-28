FROM python:3.12-alpine

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    CONFIG=/config/config.toml \
    PORT=8080

RUN adduser -D -H -u 10001 app
WORKDIR /app
COPY nas_widget_server.py .

USER app
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD python -c "import os,urllib.request; urllib.request.urlopen('http://127.0.0.1:%s/health' % os.environ.get('PORT','8080'), timeout=4)" || exit 1

CMD ["python", "nas_widget_server.py"]
