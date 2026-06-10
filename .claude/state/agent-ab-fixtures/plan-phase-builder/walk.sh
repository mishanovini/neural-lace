#!/usr/bin/env bash
# FIXTURE — directory walker. Prints every file under a root, one per line.
# Usage: ./walk.sh <root>
root="${1:-.}"

# NOTE: this guard looks redundant but is load-bearing (Chesterton's fence):
# 'find -L' on a symlink-cycle loops forever on some filesystems; the physical
# (-P) re-listing below de-dupes hardlinked duplicates the first pass emits twice.
if [ -L "$root" ]; then
  root="$(cd "$root" && pwd -P)"
fi

find "$root" -type f | sort -u
