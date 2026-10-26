"""OpenTelemetry wiring. Exports to Application Insights when a connection string is set."""

from __future__ import annotations

import logging

from fastapi import FastAPI

from .config import Settings

logger = logging.getLogger(__name__)


def configure_telemetry(app: FastAPI, settings: Settings) -> bool:
    """Enable tracing for inbound FastAPI requests and outbound httpx calls.

    Returns True when the Azure Monitor exporter was configured.
    """
    if settings.applicationinsights_connection_string is None:
        logger.info("telemetry disabled: no Application Insights connection string")
        return False

    from azure.monitor.opentelemetry import configure_azure_monitor
    from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
    from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor

    configure_azure_monitor(
        connection_string=settings.applicationinsights_connection_string.get_secret_value(),
        logger_name="genai_service",
        # Prompts and completions never become span attributes or log records.
        enable_live_metrics=False,
    )
    FastAPIInstrumentor.instrument_app(app, excluded_urls="healthz,readyz")
    HTTPXClientInstrumentor().instrument()
    return True
