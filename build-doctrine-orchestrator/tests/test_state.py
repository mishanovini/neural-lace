"""Tests for state.py — TaskState, DispatchState, and transition rules."""

from __future__ import annotations

import pytest

from build_doctrine_orchestrator.state import (
    DispatchState,
    IllegalTransitionError,
    TaskState,
    is_legal_transition,
    transition,
)


class TestTaskState:
    def test_pending_to_dispatched_is_legal(self) -> None:
        assert is_legal_transition(TaskState.PENDING, TaskState.DISPATCHED) is True

    def test_pending_to_completed_is_illegal(self) -> None:
        # Must go through DISPATCHED + IN_PROGRESS first.
        assert is_legal_transition(TaskState.PENDING, TaskState.COMPLETED) is False

    def test_completed_to_anything_is_terminal(self) -> None:
        # COMPLETED is terminal; no transitions out of it.
        for s in TaskState:
            if s == TaskState.COMPLETED:
                continue
            assert is_legal_transition(TaskState.COMPLETED, s) is False

    def test_failed_can_retry_to_pending(self) -> None:
        assert is_legal_transition(TaskState.FAILED, TaskState.PENDING) is True

    def test_blocked_can_resume_to_in_progress(self) -> None:
        assert is_legal_transition(TaskState.BLOCKED, TaskState.IN_PROGRESS) is True

    def test_full_happy_path(self) -> None:
        s = TaskState.PENDING
        s = transition(s, TaskState.DISPATCHED)
        s = transition(s, TaskState.IN_PROGRESS)
        s = transition(s, TaskState.COMPLETED)
        assert s == TaskState.COMPLETED

    def test_idempotent_self_transition(self) -> None:
        # transition(X, X) is a no-op; doesn't raise.
        for s in TaskState:
            assert transition(s, s) == s

    def test_illegal_transition_raises(self) -> None:
        with pytest.raises(IllegalTransitionError):
            transition(TaskState.PENDING, TaskState.COMPLETED)


class TestDispatchState:
    def test_initialized_to_running_is_legal(self) -> None:
        assert is_legal_transition(DispatchState.INITIALIZED, DispatchState.RUNNING) is True

    def test_running_can_pause(self) -> None:
        assert is_legal_transition(DispatchState.RUNNING, DispatchState.PAUSED) is True

    def test_paused_can_resume(self) -> None:
        assert is_legal_transition(DispatchState.PAUSED, DispatchState.RUNNING) is True

    def test_completed_is_terminal(self) -> None:
        for s in DispatchState:
            if s == DispatchState.COMPLETED:
                continue
            assert is_legal_transition(DispatchState.COMPLETED, s) is False

    def test_initialized_cannot_skip_to_completed(self) -> None:
        assert is_legal_transition(DispatchState.INITIALIZED, DispatchState.COMPLETED) is False


class TestCrossType:
    def test_task_to_dispatch_is_illegal(self) -> None:
        # Cross-type transitions never legal — TaskState and DispatchState
        # are different lifecycles.
        assert is_legal_transition(TaskState.PENDING, DispatchState.RUNNING) is False  # type: ignore[arg-type]

    def test_cross_type_transition_call_raises(self) -> None:
        with pytest.raises(IllegalTransitionError):
            transition(TaskState.PENDING, DispatchState.RUNNING)  # type: ignore[arg-type]
