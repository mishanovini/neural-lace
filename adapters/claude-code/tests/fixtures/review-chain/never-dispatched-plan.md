# Fixture: never-dispatched-reviewer plan (Task 17 variant iii material)

Status: ACTIVE

A plan fixture whose chain entry is well-formed (rules 1 and 2 both pass —
the record parses, and its attested blob three-way-matches) but names a
reviewer with ZERO rows in `dispatch-ledger.jsonl` of that type — reviewer
`harness-reviewer` never appears in this directory's `dispatch-ledger.jsonl`.
This is Task 17's D-15 acceptance-bar demo variant (iii): "a chain entry
naming a never-dispatched reviewer fails validity." Not currently wired into
`dispatch-chain-gate.sh --self-test` (Task 1 only proves the chain-less and
valid-chain shapes end-to-end); kept here as ready-made material for Task 17.

## Review Chain
plan-reviews:
  - reviewer: harness-reviewer  verdict: PASS  record: adapters/claude-code/tests/fixtures/review-chain/never-dispatched-record.md  plan-blob: 6a9a8d052151ef8f1d9487a5b652584305c4c6d2

## Goal

Exist, with a chain entry that fails ONLY rule 3.

## Tasks

- [ ] 1. Nothing real — this file is a gate-validation fixture, not a build plan.
