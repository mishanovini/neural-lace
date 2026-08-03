# Fixture: valid-chain plan (gated-pipeline-master-2026-08 Task 1)

Status: ACTIVE

A plan fixture with a fully valid `## Review Chain` block — every rule (record
parse, three-way anchor match, dispatch-ledger cross-check) passes for both
its design-reviews and plan-reviews entries. Used by `dispatch-chain-gate.sh
--check` (Task 1's "Prove it works" step 3) and by its own `--self-test` to
prove a genuinely valid chain is never blocked.

## Review Chain
authored-by: design-author (model: fable)
design-ref: adapters/claude-code/tests/fixtures/review-chain/valid-chain-design.md@a50754fe60d0f726e80afdbb28d3deb9b31d4f9c
design-reviews:
  - reviewer: architecture-reviewer  verdict: SOUND  record: adapters/claude-code/tests/fixtures/review-chain/design-review-record.md
plan-reviews:
  - reviewer: plan-fidelity-reviewer  verdict: PASS  record: adapters/claude-code/tests/fixtures/review-chain/plan-review-record.md  plan-blob: 0eb2c201f43594fad02bc74744bbf36364824dce

## Goal

Exist, and carry a Review Chain block that validates cleanly under all three
rules — the positive fixture paired with chainless-plan.md's negative one.

## Tasks

- [ ] 1. Nothing real — this file is a gate-validation fixture, not a build plan.

## In-flight scope updates
(no in-flight changes yet)
