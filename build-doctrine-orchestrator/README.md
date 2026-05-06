# build-doctrine-orchestrator

Minimal Python orchestrator for the Build Doctrine arc — the v1 scaffolding of Tranche 6.

**Status:** scaffolding only. Authored 2026-05-06. **Validation deferred** to first Python-equipped session (no Python in the authoring session). The propagation engine (C12 generalized router) is deferred until canonical-pilot empirical signal informs which PT-1..PT-7 trigger router slots actually fire most.

## Validation gap (read this first)

Every Python file in this scaffolding contains a `_TODO_PILOT_VALIDATE_` sentinel. Before extending or integrating the orchestrator, the first Python-equipped session must:

```bash
cd build-doctrine-orchestrator
pip install -e ".[dev]"

# 1. Python-syntax check (every file must compile):
python -m py_compile src/build_doctrine_orchestrator/*.py tests/*.py

# 2. Type check (mypy strict):
mypy src tests

# 3. Lint:
ruff check src tests

# 4. Run the test suite (pytest):
pytest -v

# Expected: all tests pass green. If any fail, surface to the
# Tranche 4 handoff for review BEFORE extending the scaffolding.
```

If any step above fails, do NOT proceed with Tranche 6 propagation-engine work or Tranche 7 mechanism authoring — the scaffolding has issues that need resolving first.

## What is here

```
build-doctrine-orchestrator/
├── pyproject.toml                              # project config + pytest + ruff + mypy
├── README.md                                   # this file
├── src/build_doctrine_orchestrator/
│   ├── __init__.py                             # package version + public exports
│   ├── state.py                                # TaskState, DispatchState, transition rules
│   ├── dag.py                                  # DAG class (nodes + edges + topological iteration + cycle detection)
│   └── dispatcher.py                           # Dispatcher protocol + NoopDispatcher reference impl
└── tests/
    ├── __init__.py
    ├── test_state.py                           # ~12 state-transition tests
    └── test_dag.py                             # ~20 DAG construction + iteration + cycle-detection tests
```

## Concepts

### DAG (`src/build_doctrine_orchestrator/dag.py`)

A directed acyclic graph of task IDs (strings). Edges encode prerequisites: `add_edge('A', 'B')` means "B depends on A; A must complete before B can dispatch."

```python
from build_doctrine_orchestrator import DAG

dag = DAG()
dag.add_edge('plan-task-1', 'plan-task-2')   # task 2 depends on task 1
dag.add_edge('plan-task-1', 'plan-task-3')   # task 3 also depends on task 1
dag.add_edge('plan-task-2', 'plan-task-4')   # task 4 depends on task 2
dag.add_edge('plan-task-3', 'plan-task-4')   # task 4 also depends on task 3

for task in dag.topological_iter():
    print(task)
# Output: plan-task-1, plan-task-2, plan-task-3, plan-task-4
# (relative order of 2 and 3 is lex-stable: 2 before 3)
```

Cycle detection:

```python
dag = DAG()
dag.add_edge('A', 'B')
dag.add_edge('B', 'A')   # raises CycleError; the edge is rolled back, graph remains acyclic
```

Dispatch-ready query (for orchestrator dispatch loop):

```python
completed = ['plan-task-1']
ready = dag.dispatchable(completed=completed)
# ready == frozenset({'plan-task-2', 'plan-task-3'})
```

### State (`src/build_doctrine_orchestrator/state.py`)

Two enum types and a transition-rules table:

- `TaskState`: PENDING → DISPATCHED → IN_PROGRESS → (COMPLETED | FAILED | BLOCKED). FAILED can retry to PENDING. COMPLETED is terminal.
- `DispatchState`: INITIALIZED → RUNNING → (COMPLETED | FAILED | PAUSED). PAUSED can resume to RUNNING. COMPLETED is terminal.

Cross-type transitions (Task ↔ Dispatch) are illegal — they're separate lifecycles.

```python
from build_doctrine_orchestrator import TaskState, transition

s = TaskState.PENDING
s = transition(s, TaskState.DISPATCHED)
s = transition(s, TaskState.IN_PROGRESS)
s = transition(s, TaskState.COMPLETED)   # OK
# transition(TaskState.PENDING, TaskState.COMPLETED) raises IllegalTransitionError
```

### Dispatcher (`src/build_doctrine_orchestrator/dispatcher.py`)

Protocol abstracting how a task's work actually happens. Implementations decide the mechanism (subprocess, network call, builder-spawn, no-op for tests). The reference `NoopDispatcher` always returns COMPLETED — useful for tests + as a placeholder until a real builder-spawn integration ships.

```python
from build_doctrine_orchestrator import NoopDispatcher

d = NoopDispatcher()
result = d.dispatch('my-task-id')
# result.final_state == TaskState.COMPLETED
# d.dispatched == ['my-task-id']
```

## What is NOT here (deferred)

Per the hybrid sequencing decision 2026-05-06, the following are deferred until canonical-pilot empirical signal informs the design:

- **Propagation engine (C12 generalized router)** — the doctrine flags this as the highest-leverage but observed-friction-prioritized mechanism. Building all 7 PT-* router slots cold contradicts the doctrine; pilot tells us which 1-2 actually matter.
- **Real builder-spawn integration** — the `Dispatcher` protocol is here, but the implementation that hands off to `plan-phase-builder` agents per `~/.claude/rules/orchestrator-pattern.md` is not. Pilot will inform whether this is best done via `subprocess`, the Claude Code CLI, the Anthropic API, or another integration point.
- **Cross-tranche integration** — coordination with `state-summary.sh`, `close-plan.sh`, `start-plan.sh`, and `session-wrap.sh` is not implemented in v1. The orchestrator is standalone scaffolding.
- **CI integration** — pytest config is in `pyproject.toml`, but no GitHub Actions workflow runs it yet. Wire after first successful local run.
- **Persistent state** — DAG and state are in-memory. Persistence + resume across restarts is propagation-engine territory.

## Doctrine references

- `build-doctrine/doctrine/05-implementation-process.md` — describes the orchestrator's role in the reliability spine.
- `build-doctrine/doctrine/06-propagation.md` — describes the PT-1..PT-7 trigger model the propagation engine will implement.
- `~/.claude/rules/orchestrator-pattern.md` — the lead-dispatch-builder model the orchestrator operationalizes.

## Versioning

Authored at `0.1.0`. Bump to `0.2.0` when the first runtime-validated build lands. Bump to `1.0.0` when the propagation engine is genuinely shipped + validated against pilot.
