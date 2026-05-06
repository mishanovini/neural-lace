"""DAG state machine for orchestrator dispatch.

The orchestrator reads a plan's task list and constructs a DAG where:
  - Nodes are tasks (identified by string ID).
  - Edges encode prerequisites: edge (A, B) means "B depends on A; A must
    complete before B can dispatch."
  - Topological iteration produces the dispatch order.

_TODO_PILOT_VALIDATE_: correct-by-inspection only; not runtime-tested.
"""

from __future__ import annotations

from collections import defaultdict, deque
from collections.abc import Iterable, Iterator
from dataclasses import dataclass, field


class CycleError(ValueError):
    """Raised when DAG construction or iteration detects a cycle."""


@dataclass
class DAG:
    """Directed acyclic graph of task IDs.

    Nodes are added explicitly via add_node() or implicitly via add_edge().
    Edges are directed: add_edge('A', 'B') means A must complete before B
    can start.

    Example:

        >>> dag = DAG()
        >>> dag.add_edge('A', 'B')   # B depends on A
        >>> dag.add_edge('A', 'C')   # C also depends on A
        >>> dag.add_edge('B', 'D')   # D depends on B
        >>> dag.add_edge('C', 'D')   # D depends on C
        >>> list(dag.topological_iter())
        # ['A', 'B', 'C', 'D'] or ['A', 'C', 'B', 'D'] — relative order of
        # B,C is arbitrary but stable across iterations on the same instance.
    """

    _nodes: set[str] = field(default_factory=set)
    _edges_out: dict[str, set[str]] = field(default_factory=lambda: defaultdict(set))
    _edges_in: dict[str, set[str]] = field(default_factory=lambda: defaultdict(set))

    def add_node(self, node: str) -> None:
        """Add a node. Idempotent."""
        if not isinstance(node, str) or not node:
            raise ValueError(f"node must be a non-empty string, got: {node!r}")
        self._nodes.add(node)

    def add_edge(self, from_node: str, to_node: str) -> None:
        """Add a directed edge from_node -> to_node. Raises CycleError if it would create a cycle."""
        if from_node == to_node:
            raise CycleError(f"self-loop not allowed: {from_node!r}")
        self.add_node(from_node)
        self.add_node(to_node)
        self._edges_out[from_node].add(to_node)
        self._edges_in[to_node].add(from_node)
        # Detect cycle introduced by this edge: BFS forward from to_node;
        # if we reach from_node, the new edge closes a cycle.
        if self._reachable(to_node, from_node):
            # Roll back the edge before raising.
            self._edges_out[from_node].discard(to_node)
            self._edges_in[to_node].discard(from_node)
            raise CycleError(f"adding edge {from_node!r} -> {to_node!r} would create a cycle")

    @property
    def nodes(self) -> frozenset[str]:
        """Read-only view of all nodes."""
        return frozenset(self._nodes)

    @property
    def edges(self) -> frozenset[tuple[str, str]]:
        """Read-only view of all edges as (from, to) pairs."""
        return frozenset(
            (frm, to) for frm, tos in self._edges_out.items() for to in tos
        )

    def predecessors(self, node: str) -> frozenset[str]:
        """Nodes that must complete before `node` can start."""
        if node not in self._nodes:
            raise KeyError(f"unknown node: {node!r}")
        return frozenset(self._edges_in.get(node, set()))

    def successors(self, node: str) -> frozenset[str]:
        """Nodes that depend on `node`."""
        if node not in self._nodes:
            raise KeyError(f"unknown node: {node!r}")
        return frozenset(self._edges_out.get(node, set()))

    def detect_cycles(self) -> None:
        """Walk the graph; raise CycleError if any cycle exists. No-op for an acyclic DAG."""
        # Use the topological-iter implementation as the cycle detector.
        list(self.topological_iter())

    def topological_iter(self) -> Iterator[str]:
        """Yield nodes in dependency order (Kahn's algorithm).

        Stable: when multiple nodes are simultaneously dispatchable, they are
        yielded in lexicographic order of their IDs. This makes the iteration
        deterministic across runs.
        """
        in_degree: dict[str, int] = {n: len(self._edges_in.get(n, set())) for n in self._nodes}
        # Use sorted to make iteration order deterministic.
        ready: deque[str] = deque(sorted(n for n, d in in_degree.items() if d == 0))
        emitted: list[str] = []
        while ready:
            current = ready.popleft()
            emitted.append(current)
            yield current
            # Decrement in-degree of each successor; sort newly-zero successors.
            new_ready: list[str] = []
            for succ in sorted(self._edges_out.get(current, set())):
                in_degree[succ] -= 1
                if in_degree[succ] == 0:
                    new_ready.append(succ)
            ready.extend(new_ready)
        if len(emitted) != len(self._nodes):
            unemitted = self._nodes - set(emitted)
            raise CycleError(f"cycle detected; un-emitted nodes: {sorted(unemitted)!r}")

    def dispatchable(self, completed: Iterable[str]) -> frozenset[str]:
        """Given the set of completed nodes, return nodes whose all predecessors are completed
        and which themselves are not yet completed."""
        completed_set = set(completed)
        return frozenset(
            n
            for n in self._nodes
            if n not in completed_set
            and self._edges_in.get(n, set()).issubset(completed_set)
        )

    def _reachable(self, start: str, target: str) -> bool:
        """Return True if target is reachable from start via forward edges."""
        if start not in self._nodes:
            return False
        seen: set[str] = set()
        stack: list[str] = [start]
        while stack:
            current = stack.pop()
            if current == target:
                return True
            if current in seen:
                continue
            seen.add(current)
            stack.extend(self._edges_out.get(current, set()))
        return False
