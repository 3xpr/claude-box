#!/usr/bin/env bash
# Tests bin/cbox against a fake `docker` that prints its arguments one per line.
# Needs no real Docker.
set -euo pipefail

box="$(cd "$(dirname "$0")/.." && pwd)"
cbox="$box/bin/cbox"
fail() { echo "FAIL: $*" >&2; exit 1; }

fake="$(mktemp -d)"
printf '#!/bin/sh\nprintf "%%s\\n" "$@"\n' > "$fake/docker"
chmod +x "$fake/docker"
proj="$(cd "$(mktemp -d)" && pwd -P)"   # physical path: cbox mounts pwd -P

# 1. Refuses to mount / or $HOME
(cd / && PATH="$fake:$PATH" "$cbox" >/dev/null 2>&1) && fail "did not refuse /"
(cd "$HOME" && PATH="$fake:$PATH" "$cbox" >/dev/null 2>&1) && fail "did not refuse \$HOME"
(cd "$box" && PATH="$fake:$PATH" "$cbox" >/dev/null 2>&1) && fail "did not refuse its own repo"

# 2. Clear error when docker is absent
(cd "$proj" && PATH="/usr/bin:/bin" "$cbox" 2>&1 || true) | grep -q "docker not found" \
  || fail "no 'docker not found' message"

# 3. Exact docker arguments
out="$(cd "$proj" && PATH="$fake:$PATH" "$cbox" --version)" || fail "cbox exited non-zero in a project dir"
expect() { grep -Fxq -- "$1" <<<"$out" || fail "missing docker arg: $1"; }
expect "run"
expect "--rm"
expect "-it"
expect "--env-file"
expect "$box/.env"
expect "claude-dev-home:/home/dev"
expect "$proj:$proj"
expect "$box/home/CLAUDE.md:/home/dev/.claude/CLAUDE.md:ro"
expect "-w"
expect "$proj"
expect "claude-box"
expect "claude"
expect "--version"

rm -rf "$fake" "$proj"
echo "cbox_test OK"
