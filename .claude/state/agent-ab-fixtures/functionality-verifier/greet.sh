#!/usr/bin/env bash
# FIXTURE script — task T-FV-1 claims: "greet.sh prints 'Hello, <name>!' for a
# given name AND exits non-zero with a usage message when the name is empty/missing."
#
# Usage: ./greet.sh <name>
#        ./greet.sh --self-test

if [ "$1" = "--self-test" ]; then
  out="$(bash "$0" Ada)"
  if [ "$out" = "Hello, Ada!" ]; then
    echo "self-test: 1/1 PASS"
    exit 0
  else
    echo "self-test: FAIL (got: $out)"
    exit 1
  fi
fi

# BUG (planted): empty/missing name is NOT rejected — prints 'Hello, !' and exits 0.
echo "Hello, $1!"
exit 0
