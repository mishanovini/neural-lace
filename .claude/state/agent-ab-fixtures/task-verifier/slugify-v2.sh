#!/usr/bin/env bash
# FIXTURE — the "refactored" replacement the builder produced for task T-TV-1.
# PLANTED BEHAVIORAL DIFFERENCE: does NOT collapse consecutive dashes.
s="$1"
s="$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]' | tr ' _' '--' | sed 's/[^a-z0-9-]//g; s/^-//; s/-$//')"
printf '%s\n' "$s"
