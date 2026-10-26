# syntax=docker/dockerfile:1.7
# Build from the repository root: docker build -f app/Dockerfile -t genai-service .

FROM python:3.11-slim-bookworm AS build
ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1
WORKDIR /src
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"
COPY pyproject.toml ./
COPY app/README.md app/README.md
COPY app/src app/src
RUN pip install --upgrade "pip>=24.3" && pip install .

FROM python:3.11-slim-bookworm AS runtime
LABEL org.opencontainers.image.title="genai-service" \
      org.opencontainers.image.description="Sample workload behind a secure Azure OpenAI gateway" \
      org.opencontainers.image.licenses="MIT"
ENV PATH="/opt/venv/bin:${PATH}" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1
RUN groupadd --system --gid 10001 app \
    && useradd --system --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app
COPY --from=build /opt/venv /opt/venv
USER 10001:10001
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD ["python", "-c", "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8080/healthz', timeout=2).status == 200 else 1)"]
ENTRYPOINT ["uvicorn", "--factory", "genai_service.main:create_app", "--host", "0.0.0.0", "--port", "8080", "--proxy-headers", "--no-server-header"]
