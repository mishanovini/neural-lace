"""Build Doctrine Orchestrator — scaffolding (Tranche 6, 2026-05-06).

Minimal Python orchestrator for the Build Doctrine arc. Provides a DAG
state machine + dispatch protocol that downstream tranches build on. The
generalized propagation engine (C12) is deferred until canonical-pilot
empirical signal informs which PT-1..PT-7 trigger router slots actually
fire most.

_TODO_PILOT_VALIDATE_: this scaffolding is correct-by-inspection but
has not been runtime-validated locally (no Python in the authoring
session). First Python-equipped session must:

  $ cd build-doctrine-orchestrator
  $ pip install -e ".[dev]"
  $ pytest

If any test fails, surface to the Tranche 4 handoff for review BEFORE
extending the scaffolding.
"""

__version__ = "0.1.0"

from build_doctrine_orchestrator.dag import DAG, CycleError
from build_doctrine_orchestrator.dispatcher import Dispatcher, NoopDispatcher
from build_doctrine_orchestrator.state import (
    DispatchState,
    IllegalTransitionError,
    TaskState,
    is_legal_transition,
)

__all__ = [
    "DAG",
    "CycleError",
    "Dispatcher",
    "NoopDispatcher",
    "DispatchState",
    "IllegalTransitionError",
    "TaskState",
    "is_legal_transition",
    "__version__",
]
