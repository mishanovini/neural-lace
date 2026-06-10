#!/usr/bin/env bash
# FIXTURE — the PRE-EXISTING test suite for slugify (the oracle).
# Run against any implementation: TARGET=./slugify-v2.sh ./original-tests.sh
TARGET="${TARGET:-./slugify.sh}"
cd "$(dirname "$0")"
pass=0; fail=0
check() { out="$(bash "$TARGET" "$1")"; if [ "$out" = "$2" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: '$1' -> '$out' (want '$2')"; fi; }
check "Hello World" "hello-world"
check "a_b c" "a-b-c"
check "Foo  Bar" "foo-bar"        # double space must collapse
check "x--y" "x-y"                # consecutive dashes must collapse
check "  trim me  " "trim-me"
check "Symbols!@#" "symbols"
echo "original suite: $pass passed, $fail failed"
[ $fail -eq 0 ]
