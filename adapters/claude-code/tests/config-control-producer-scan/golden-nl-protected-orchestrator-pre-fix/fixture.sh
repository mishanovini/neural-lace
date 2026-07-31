#!/bin/bash
# fixture: the SAME read site as the post-fix golden fixture, with the
# honest-status annotation stripped -- reproducing what
# hooks/lib/admission-lib.sh looked like BEFORE the 2026-07-29
# task-verifier pass added its callout comment. Proves the scan keys on
# the marker text, not the variable name: identical code, only the
# comment differs, and the classification must flip to the vaporware
# verdict.

#   NL_PROTECTED_ORCHESTRATOR=1    -> caller-declared, unverified; any process
#                                     can exclude its own traffic from the
#                                     "pathology" bucket in the calibration
#                                     this slice exists to produce

adm_admit() {
  local protected=0
  [[ "${NL_PROTECTED_ORCHESTRATOR:-0}" == "1" ]] && protected=1
  echo "protected=$protected"
}
