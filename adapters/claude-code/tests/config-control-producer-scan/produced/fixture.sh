#!/bin/bash
# fixture: a config lever with a real, standalone producer somewhere in
# the same scan root. Should classify PRODUCED.

export NL_FIXTURE_PRODUCED=1

if [[ "${NL_FIXTURE_PRODUCED:-0}" == "1" ]]; then
  echo "fixture: produced lever is active"
fi
