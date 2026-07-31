#!/bin/bash
# fixture: a config lever with NO producer, but an honest-status marker
# comment sitting near the read site. Should classify MARKED, not
# FLAGGED.

#   NL_FIXTURE_MARKED=1  -> caller-declared, unverified; any process
#       HONEST STATUS (fixture): no producer sets this variable anywhere
#       in this fixture tree today -- the read below is a documented,
#       not-yet-wired lever, same shape as the real
#       admission-lib.sh NL_PROTECTED_ORCHESTRATOR annotation.

if [[ "${NL_FIXTURE_MARKED:-0}" == "1" ]]; then
  echo "fixture: marked lever is active"
fi
