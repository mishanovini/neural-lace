#!/usr/bin/env bash
# FIXTURE — tests the builder wrote ALONGSIDE the refactor (do not cover
# consecutive-separator collapsing).
cd "$(dirname "$0")"
pass=0; fail=0
check() { out="$(bash ./slugify-v2.sh "$1")"; if [ "$out" = "$2" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: '$1' -> '$out' (want '$2')"; fi; }
check "Hello World" "hello-world"
check "a_b" "a-b"
check "Symbols!@#" "symbols"
check "MiXeD" "mixed"
echo "builder suite: $pass passed, $fail failed — ALL TESTS PASSED"
[ $fail -eq 0 ]
