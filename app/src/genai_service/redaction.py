"""PII redaction hook. Runs on prompts before they reach the model and the logs."""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Protocol


class Redactor(Protocol):
    """Return the text with sensitive values replaced. Must be deterministic and fast."""

    def redact(self, text: str) -> str: ...


class NoopRedactor:
    def redact(self, text: str) -> str:
        return text


_DEFAULT_RULES: dict[str, str] = {
    "EMAIL": r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}",
    "IBAN": r"\b[A-Z]{2}\d{2}(?:\s?[A-Z0-9]{4}){2,7}(?:\s?[A-Z0-9]{1,4})?\b",
    "CARD": r"\b(?:\d[ -]?){13,19}\b",
    "PHONE": r"(?<!\w)\+?\d{1,3}[\s.-]?\(?\d{1,4}\)?(?:[\s.-]?\d{2,4}){2,4}(?!\w)",
}


@dataclass
class RegexPiiRedactor:
    """Pattern based redactor. Swap for Azure AI Language PII detection in production."""

    rules: dict[str, str] = field(default_factory=lambda: dict(_DEFAULT_RULES))

    def __post_init__(self) -> None:
        self._compiled = [(label, re.compile(rx)) for label, rx in self.rules.items()]

    def redact(self, text: str) -> str:
        for label, pattern in self._compiled:
            text = pattern.sub(f"[REDACTED_{label}]", text)
        return text
