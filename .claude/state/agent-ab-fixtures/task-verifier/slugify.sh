#!/usr/bin/env bash
# FIXTURE — original util. Contract (from its test suite): lowercase, spaces and
# underscores -> dash, strip non-alphanumerics, COLLAPSE consecutive dashes, trim
# leading/trailing dashes.
s="$1"
s="$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]' | tr ' _' '--' | sed 's/[^a-z0-9-]//g; s/--*/-/g; s/^-//; s/-$//')"
printf '%s\n' "$s"
