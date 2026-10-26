from __future__ import annotations

import pytest

from genai_service.redaction import NoopRedactor, RegexPiiRedactor


@pytest.mark.parametrize(
    ("text", "label"),
    [
        ("contact jane.doe@example.com today", "EMAIL"),
        ("card 4111 1111 1111 1111 expires soon", "CARD"),
        ("wire to FR76 3000 6000 0112 3456 7890 189", "IBAN"),
        ("call +33 6 12 34 56 78 tomorrow", "PHONE"),
    ],
)
def test_redacts_common_pii(text: str, label: str) -> None:
    redacted = RegexPiiRedactor().redact(text)
    assert f"[REDACTED_{label}]" in redacted


def test_leaves_clean_text_untouched() -> None:
    text = "Deploy version 2 of the service in westeurope."
    assert RegexPiiRedactor().redact(text) == text


def test_custom_rule() -> None:
    redactor = RegexPiiRedactor(rules={"EMPLOYEE": r"\bEMP-\d{6}\b"})
    assert redactor.redact("ticket for EMP-123456") == "ticket for [REDACTED_EMPLOYEE]"


def test_noop_redactor() -> None:
    assert NoopRedactor().redact("a@b.co") == "a@b.co"
