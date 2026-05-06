"""Task + dispatch state types and transition rules.

_TODO_PILOT_VALIDATE_: correct-by-inspection only; not runtime-tested.
"""

from __future__ import annotations

from enum import Enum


class TaskState(str, Enum):
    """Per-task lifecycle state."""

    PENDING = "pending"
    DISPATCHED = "dispatched"
    IN_PROGRESS = "in_progress"
    BLOCKED = "blocked"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


class DispatchState(str, Enum):
    """Per-orchestrator-run lifecycle state."""

    INITIALIZED = "initialized"
    RUNNING = "running"
    PAUSED = "paused"
    COMPLETED = "completed"
    FAILED = "failed"


class IllegalTransitionError(ValueError):
    """Raised when a state transition is not in the legal-transitions table."""


# Legal task-state transitions. Each entry: (from_state, to_state).
# The list is canonical — anything not here is illegal.
_LEGAL_TASK_TRANSITIONS: frozenset[tuple[TaskState, TaskState]] = frozenset(
    {
        (TaskState.PENDING, TaskState.DISPATCHED),
        (TaskState.PENDING, TaskState.CANCELLED),
        (TaskState.DISPATCHED, TaskState.IN_PROGRESS),
        (TaskState.DISPATCHED, TaskState.BLOCKED),
        (TaskState.DISPATCHED, TaskState.CANCELLED),
        (TaskState.IN_PROGRESS, TaskState.COMPLETED),
        (TaskState.IN_PROGRESS, TaskState.FAILED),
        (TaskState.IN_PROGRESS, TaskState.BLOCKED),
        (TaskState.IN_PROGRESS, TaskState.CANCELLED),
        (TaskState.BLOCKED, TaskState.IN_PROGRESS),
        (TaskState.BLOCKED, TaskState.CANCELLED),
        (TaskState.BLOCKED, TaskState.FAILED),
        (TaskState.FAILED, TaskState.PENDING),  # retry path
        (TaskState.FAILED, TaskState.CANCELLED),
    }
)

# Legal dispatch-state transitions.
_LEGAL_DISPATCH_TRANSITIONS: frozenset[tuple[DispatchState, DispatchState]] = frozenset(
    {
        (DispatchState.INITIALIZED, DispatchState.RUNNING),
        (DispatchState.RUNNING, DispatchState.PAUSED),
        (DispatchState.RUNNING, DispatchState.COMPLETED),
        (DispatchState.RUNNING, DispatchState.FAILED),
        (DispatchState.PAUSED, DispatchState.RUNNING),
        (DispatchState.PAUSED, DispatchState.FAILED),
    }
)


def is_legal_transition(
    from_state: TaskState | DispatchState, to_state: TaskState | DispatchState
) -> bool:
    """Return True if the transition is in the legal-transitions table."""
    if isinstance(from_state, TaskState) and isinstance(to_state, TaskState):
        return (from_state, to_state) in _LEGAL_TASK_TRANSITIONS
    if isinstance(from_state, DispatchState) and isinstance(to_state, DispatchState):
        return (from_state, to_state) in _LEGAL_DISPATCH_TRANSITIONS
    # Cross-type transitions are not legal (Task <-> Dispatch never).
    return False


def transition(
    from_state: TaskState | DispatchState, to_state: TaskState | DispatchState
) -> TaskState | DispatchState:
    """Validate + return the new state. Raises IllegalTransitionError on failure."""
    if from_state == to_state:
        return to_state  # no-op; idempotent
    if not is_legal_transition(from_state, to_state):
        raise IllegalTransitionError(
            f"illegal transition: {from_state.value} -> {to_state.value}"
        )
    return to_state
