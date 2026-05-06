"""Tests for dag.py — DAG construction, iteration, cycle detection."""

from __future__ import annotations

import pytest

from build_doctrine_orchestrator.dag import DAG, CycleError


class TestConstruction:
    def test_empty_dag(self) -> None:
        dag = DAG()
        assert dag.nodes == frozenset()
        assert dag.edges == frozenset()
        assert list(dag.topological_iter()) == []

    def test_add_single_node(self) -> None:
        dag = DAG()
        dag.add_node("A")
        assert dag.nodes == {"A"}
        assert dag.edges == frozenset()
        assert list(dag.topological_iter()) == ["A"]

    def test_add_node_idempotent(self) -> None:
        dag = DAG()
        dag.add_node("A")
        dag.add_node("A")
        assert dag.nodes == {"A"}

    def test_add_node_empty_string_rejected(self) -> None:
        dag = DAG()
        with pytest.raises(ValueError):
            dag.add_node("")

    def test_add_node_non_string_rejected(self) -> None:
        dag = DAG()
        with pytest.raises(ValueError):
            dag.add_node(123)  # type: ignore[arg-type]

    def test_add_edge_creates_nodes(self) -> None:
        dag = DAG()
        dag.add_edge("A", "B")
        assert dag.nodes == {"A", "B"}
        assert ("A", "B") in dag.edges


class TestCycleDetection:
    def test_self_loop_raises(self) -> None:
        dag = DAG()
        with pytest.raises(CycleError):
            dag.add_edge("A", "A")

    def test_two_node_cycle_raises(self) -> None:
        dag = DAG()
        dag.add_edge("A", "B")
        with pytest.raises(CycleError):
            dag.add_edge("B", "A")

    def test_three_node_cycle_raises(self) -> None:
        dag = DAG()
        dag.add_edge("A", "B")
        dag.add_edge("B", "C")
        with pytest.raises(CycleError):
            dag.add_edge("C", "A")

    def test_failed_edge_does_not_persist(self) -> None:
        # When add_edge raises CycleError, the edge must NOT be in the graph.
        dag = DAG()
        dag.add_edge("A", "B")
        dag.add_edge("B", "C")
        with pytest.raises(CycleError):
            dag.add_edge("C", "A")
        # Verify C->A is NOT present after rollback.
        assert ("C", "A") not in dag.edges

    def test_detect_cycles_passes_acyclic(self) -> None:
        dag = DAG()
        dag.add_edge("A", "B")
        dag.add_edge("A", "C")
        dag.add_edge("B", "D")
        dag.add_edge("C", "D")
        dag.detect_cycles()  # should not raise


class TestTopologicalIteration:
    def test_chain_order(self) -> None:
        dag = DAG()
        dag.add_edge("A", "B")
        dag.add_edge("B", "C")
        assert list(dag.topological_iter()) == ["A", "B", "C"]

    def test_diamond_order_d_last(self) -> None:
        # A -> B, A -> C, B -> D, C -> D. D must be last.
        dag = DAG()
        dag.add_edge("A", "B")
        dag.add_edge("A", "C")
        dag.add_edge("B", "D")
        dag.add_edge("C", "D")
        order = list(dag.topological_iter())
        assert order[0] == "A"
        assert order[-1] == "D"
        assert set(order[1:3]) == {"B", "C"}

    def test_lex_stable_for_independent_nodes(self) -> None:
        # When two roots have no dependency on each other, lex order applies.
        dag = DAG()
        dag.add_node("Z")
        dag.add_node("A")
        order = list(dag.topological_iter())
        assert order == ["A", "Z"]

    def test_disconnected_subgraphs(self) -> None:
        dag = DAG()
        dag.add_edge("A", "B")
        dag.add_edge("C", "D")
        order = list(dag.topological_iter())
        assert "A" in order and "B" in order and "C" in order and "D" in order
        # A before B, C before D; relative order between subgraphs by lex.
        assert order.index("A") < order.index("B")
        assert order.index("C") < order.index("D")


class TestPredecessorsSuccessors:
    def test_predecessors_empty_for_root(self) -> None:
        dag = DAG()
        dag.add_edge("A", "B")
        assert dag.predecessors("A") == frozenset()

    def test_predecessors_for_dependent(self) -> None:
        dag = DAG()
        dag.add_edge("A", "C")
        dag.add_edge("B", "C")
        assert dag.predecessors("C") == frozenset({"A", "B"})

    def test_successors_empty_for_leaf(self) -> None:
        dag = DAG()
        dag.add_edge("A", "B")
        assert dag.successors("B") == frozenset()

    def test_successors_for_root(self) -> None:
        dag = DAG()
        dag.add_edge("A", "B")
        dag.add_edge("A", "C")
        assert dag.successors("A") == frozenset({"B", "C"})

    def test_unknown_node_raises(self) -> None:
        dag = DAG()
        with pytest.raises(KeyError):
            dag.predecessors("X")


class TestDispatchable:
    def test_dispatchable_initial_state(self) -> None:
        dag = DAG()
        dag.add_edge("A", "B")
        dag.add_edge("A", "C")
        assert dag.dispatchable(completed=[]) == frozenset({"A"})

    def test_dispatchable_after_a_completes(self) -> None:
        dag = DAG()
        dag.add_edge("A", "B")
        dag.add_edge("A", "C")
        assert dag.dispatchable(completed=["A"]) == frozenset({"B", "C"})

    def test_dispatchable_after_all_complete(self) -> None:
        dag = DAG()
        dag.add_edge("A", "B")
        assert dag.dispatchable(completed=["A", "B"]) == frozenset()
