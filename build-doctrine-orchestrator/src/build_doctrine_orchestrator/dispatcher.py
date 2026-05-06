"""Dispatcher protocol + reference implementation.

The orchestrator drives a Dispatcher to actually execute tasks. The
Dispatcher protocol abstracts execution so that tests can use NoopDispatcher,
production can use a real builder-spawn integration, and the canonical-pilot
session can experiment with different dispatch backends.

_TODO_PILOT_VALIDATE_: correct-by-inspection only; not runtime-tested.
The pilot session will likely extend this with a real builder-spawn
integration that hands off to plan-phase-builder agents per
~/.claude/rules/orchestrator-pattern.md. That integration is NOT part of
v1 scaffolding.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Protocol, runtime_checkable

from build_doctrine_orchestrator.state import TaskState


@dataclass(frozen=True)
class DispatchResult:
    """Outcome of a single task dispatch."""

    task_id: str
    final_state: TaskState
    summary: str = ""
    error: str | None = None


@runtime_checkable
class Dispatcher(Protocol):
    """Dispatcher protocol — anything implementing dispatch(task_id) -> DispatchResult.

    Implementations decide HOW the work is performed (subprocess, network call,
    builder-spawn, no-op for tests). The orchestrator only cares about the
    final state.
    """

    def dispatch(self, task_id: str) -> DispatchResult:
        """Dispatch the named task. Returns the result with a final state."""
        ...


@dataclass
class NoopDispatcher:
    """Reference Dispatcher that always succeeds. Used in tests + as a default.

    Tracks dispatch order in `dispatched` for assertion in tests.
    """

    dispatched: list[str] = field(default_factory=list)

    def dispatch(self, task_id: str) -> DispatchResult:
        if not isinstance(task_id, str) or not task_id:
            raise ValueError(f"task_id must be a non-empty string, got: {task_id!r}")
        self.dispatched.append(task_id)
        return DispatchResult(
            task_id=task_id,
            final_state=TaskState.COMPLETED,
            summary=f"NoopDispatcher: {task_id} marked completed without execution",
        )
