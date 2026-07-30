#!/bin/bash
# fixture: reproduction of the REAL current text in
# hooks/lib/admission-lib.sh (the HARNESS-GAP-57 golden scenario, POST
# fix). The honest-status annotation is present, so this should
# classify MARKED, not FLAGGED, despite having zero producers.

#   NL_PROTECTED_ORCHESTRATOR=1    -> caller-declared, unverified; any process
#       HONEST STATUS (2026-07-29, task-verifier pass 4 D-4): NO producer sets
#       this variable anywhere in the repo today -- all 888 live ledger rows
#       carry protected:0, so the protected/storm discriminator is INERT until
#       a dispatcher exports it. This header is a contract awaiting its first
#       caller, not a description of current traffic.

adm_admit() {
  local protected=0
  [[ "${NL_PROTECTED_ORCHESTRATOR:-0}" == "1" ]] && protected=1
  echo "protected=$protected"
}
