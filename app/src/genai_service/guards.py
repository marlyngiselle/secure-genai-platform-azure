"""Input guardrails applied before any prompt leaves the service.

These checks are a first, cheap line of defence. They complement, and never replace,
Azure AI Content Safety and the content filters configured on the model deployment.
"""

from __future__ import annotations

import re
from collections.abc import Iterable, Sequence
from dataclasses import dataclass, field
from typing import Protocol


class PromptRejectedError(Exception):
    """Raised when a prompt fails a guard. The reason is safe to return to the caller."""

    def __init__(self, reason: str) -> None:
        super().__init__(reason)
        self.reason = reason


class DenylistHook(Protocol):
    """Pluggable check. Return a reason string to reject, or None to accept."""

    def __call__(self, text: str) -> str | None: ...


DEFAULT_INJECTION_PATTERNS: tuple[str, ...] = (
    r"ignore\s+(all\s+)?(previous|prior|above)\s+instructions",
    r"disregard\s+(the\s+)?(system|previous)\s+(prompt|instructions)",
    r"reveal\s+(your|the)\s+(system\s+prompt|instructions)",
    r"you\s+are\s+now\s+(in\s+)?(developer|dan|jailbreak)\s+mode",
)


@dataclass(frozen=True)
class RegexDenylist:
    """Reject text matching any of the configured patterns (case insensitive)."""

    patterns: Sequence[str] = DEFAULT_INJECTION_PATTERNS
    _compiled: tuple[re.Pattern[str], ...] = field(init=False, repr=False)

    def __post_init__(self) -> None:
        compiled = tuple(re.compile(p, re.IGNORECASE) for p in self.patterns)
        object.__setattr__(self, "_compiled", compiled)

    def __call__(self, text: str) -> str | None:
        for pattern in self._compiled:
            if pattern.search(text):
                return "prompt matches a blocked instruction pattern"
        return None


@dataclass
class PromptGuard:
    """Validate a conversation before it is sent to the gateway."""

    max_input_chars: int = 8000
    max_messages: int = 40
    hooks: list[DenylistHook] = field(default_factory=lambda: [RegexDenylist()])

    def check(self, contents: Iterable[str]) -> None:
        items = list(contents)
        if not items:
            raise PromptRejectedError("conversation is empty")
        if len(items) > self.max_messages:
            raise PromptRejectedError(f"conversation exceeds {self.max_messages} messages")
        total = sum(len(text) for text in items)
        if total > self.max_input_chars:
            raise PromptRejectedError(f"input exceeds {self.max_input_chars} characters")
        for text in items:
            if "\x00" in text:
                raise PromptRejectedError("input contains control characters")
            for hook in self.hooks:
                reason = hook(text)
                if reason is not None:
                    raise PromptRejectedError(reason)
