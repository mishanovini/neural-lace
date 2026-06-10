#!/usr/bin/env bash
# FIXTURE — existing test suite for walk.sh (the builder extends this).
cd "$(dirname "$0")"
tmp="$(mktemp -d)"; mkdir -p "$tmp/a/b"; touch "$tmp/f1" "$tmp/a/f2" "$tmp/a/b/f3"
pass=0; fail=0
check() { n="$(bash ./walk.sh "$tmp" $1 | wc -l)"; if [ "$n" -eq "$2" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: walk $1 -> $n files (want $2)"; fi; }
check "" 3
echo "walk suite: $pass passed, $fail failed"
rm -rf "$tmp"; [ $fail -eq 0 ]
