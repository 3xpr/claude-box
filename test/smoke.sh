#!/usr/bin/env bash
# Runs inside the claude-box image. Asserts the spec's image-level requirements.
set -euo pipefail
fail() { echo "FAIL: $*" >&2; exit 1; }

[ "$(whoami)" = dev ]                          || fail "user is $(whoami), expected dev"
[ "$HOME" = /home/dev ]                        || fail "HOME is $HOME"
[ "$(id -u)" = 1000 ]                          || fail "uid is $(id -u)"
[ "${DISABLE_AUTOUPDATER:-}" = 1 ]             || fail "DISABLE_AUTOUPDATER not 1"

claude --version                               || fail "claude missing"
node --version                                 || fail "node missing"
npm --version                                  || fail "npm missing"
mise --version                                 || fail "mise missing"
command -v git   >/dev/null                    || fail "git missing"
command -v ps    >/dev/null                    || fail "procps missing"
! command -v sudo >/dev/null                   || fail "sudo present"

[ "$(stat -c %U "$HOME/.claude")" = dev ]      || fail "~/.claude not owned by dev"
node -e 'JSON.parse(require("fs").readFileSync(process.env.HOME+"/.claude/settings.json","utf8"))' \
                                               || fail "settings.json invalid"
echo "smoke OK"
