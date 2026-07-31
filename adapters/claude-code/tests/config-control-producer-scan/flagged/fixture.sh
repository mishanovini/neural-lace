#!/bin/bash
# fixture: a config lever with NO producer and NO nearby marker comment.
# This is the vaporware shape this scan exists to catch -- the golden
# scenario's pre-fix shape (a real read site, a real branch, nothing
# ever sets it). Should classify FLAGGED, exit 1.

if [[ "${NL_FIXTURE_FLAGGED:-0}" == "1" ]]; then
  echo "fixture: flagged lever is active"
fi
