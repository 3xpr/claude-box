# claude-box Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A `cbox` command that runs Claude Code in a throwaway Docker container which sees only the current project directory and one persistent home volume.

**Architecture:** A Debian image holds the tools (Claude Code via apt, mise, git). A named volume `claude-dev-home` mounted at `/home/dev` holds all state. A bash wrapper bind-mounts `$PWD` at its own path, bind-mounts the repo's `CLAUDE.md` read-only, and execs `docker run`.

**Tech Stack:** Docker (OrbStack on macOS), `debian:13-slim`, Claude Code apt repo, mise, bash.

**Spec:** `docs/superpowers/specs/2026-09-18-claude-box-design.md`

## Global Constraints

- Do not `git commit` anything. Joel commits himself.
- Never add `Co-Authored-By` or any Claude attribution to commit messages.
- Container user is `dev`, uid `1000`, home `/home/dev`. No `sudo` in the image.
- Volume name is exactly `claude-dev-home`. Image tag is exactly `claude-box`.
- Claude Code is installed from the apt repo `latest` channel with `DISABLE_AUTOUPDATER=1`.
- Git identity seeded in the container: name `Your Name`, email `you@example.com`.
- Host is macOS arm64 (`uname -m` → `arm64`). `readlink -f` is available. `~/.local/bin` is on `PATH`. Homebrew is at `/opt/homebrew/bin/brew`.
- All paths below are relative to `/Users/joeldickey/repo/claude-box/` unless absolute.

## File Structure

| File | Responsibility |
|---|---|
| `home/CLAUDE.md` | Global instructions Claude reads inside the container; bind-mounted read-only every run |
| `home/settings.json` | `autoMode.environment` for the classifier; seeded into the volume once |
| `home/.gitconfig` | Git identity; seeded into the volume once |
| `bin/cbox` | Wrapper: guards, then `exec docker run …` |
| `test/cbox_test.sh` | Tests the wrapper against a fake `docker` that echoes its arguments; needs no Docker |
| `Dockerfile` | Image: Debian, Claude Code, mise + Node LTS, `dev` user, seeded home |
| `test/smoke.sh` | Runs inside the built image; asserts tools, user, env, seeded files |
| `README.md` | Build, install, first run, emergency shell, re-seed |

---

### Task 1: Home seed files

**Files:**
- Create: `home/CLAUDE.md`
- Create: `home/settings.json`
- Create: `home/.gitconfig`

**Interfaces:**
- Consumes: nothing
- Produces: the three files the Dockerfile `COPY`s (Task 4) and the wrapper bind-mounts (Task 2). Paths are fixed; later tasks reference them verbatim.

- [ ] **Step 1: Write the check and see it fail**

Run from the repo root:

```bash
node -e 'JSON.parse(require("fs").readFileSync("home/settings.json","utf8")); console.log("settings ok")' \
 && [ "$(git config -f home/.gitconfig user.name)" = Your Name ] \
 && [ "$(git config -f home/.gitconfig user.email)" = you@example.com ] \
 && grep -q 'Co-Authored-By' home/CLAUDE.md \
 && echo "seed ok"
```

Expected: fails with `ENOENT … home/settings.json`.

- [ ] **Step 2: Create `home/CLAUDE.md`**

```markdown
# Environment

You are running inside a Docker container (`claude-box`). Facts:

- Only the current project directory is mounted from the host, at its real host path. Nothing else on the host exists here. If you need something that seems to be missing — another repo, a dotfile, a config, a sibling project — do not search for it here; tell Joel what you need and where you expect it to be on the host.
- `/home/dev` is a persistent volume. Login, settings, session history, and mise-installed Node versions survive between runs. Everything else is discarded when the session ends.
- There is no `sudo` and no `apt`. If a system package is missing, say so and ask Joel to add it to `~/repo/claude-box/Dockerfile` on the host.
- Node is managed by mise. A global LTS is installed. If the project pins a version (`.mise.toml`, `.node-version`, `.tool-versions`), run `mise trust && mise install` once.
- No SSH keys or tokens are mounted. `git commit` works; `git push` does not — leave pushing to Joel.
- Never add a `Co-Authored-By` trailer or any other Claude attribution to commit messages.
- No container ports are published. Dev servers run, but Joel cannot open them in a host browser; test with `curl` inside instead.
```

- [ ] **Step 3: Create `home/settings.json`**

```json
{
  "autoMode": {
    "environment": [
      "**Isolation**: Docker container. Only the current project directory is bind-mounted from the host at its real path; nothing else on the host is reachable.",
      "**Secrets**: none mounted — no SSH keys, no cloud credentials, no tokens beyond Claude Code's own login.",
      "**Network**: unrestricted egress; no host ports published.",
      "**Trusted repo**: the mounted project directory (the container's working directory)."
    ]
  }
}
```

- [ ] **Step 4: Create `home/.gitconfig`**

Tab-indented, as git writes it:

```ini
[user]
	name = Your Name
	email = you@example.com
```

- [ ] **Step 5: Re-run the check**

Same command as Step 1. Expected output:

```
settings ok
seed ok
```

---

### Task 2: Wrapper `bin/cbox`

**Files:**
- Create: `bin/cbox`
- Create: `test/cbox_test.sh`

**Interfaces:**
- Consumes: `home/CLAUDE.md` (Task 1) — bind-mounted by absolute path derived from the script's own location.
- Produces: the command `cbox [claude args…]`. Exact `docker run` argument list, in order:
  `run --rm -it -v claude-dev-home:/home/dev -v "$PWD:$PWD" -v "$box/home/CLAUDE.md:/home/dev/.claude/CLAUDE.md:ro" -w "$PWD" claude-box claude "$@"`
  Task 4's image must be tagged `claude-box` and provide `claude` on `PATH`.

- [ ] **Step 1: Write the failing test `test/cbox_test.sh`**

```bash
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
proj="$(mktemp -d)"

# 1. Refuses to mount / or $HOME
(cd / && PATH="$fake:$PATH" "$cbox" >/dev/null 2>&1) && fail "did not refuse /"
(cd "$HOME" && PATH="$fake:$PATH" "$cbox" >/dev/null 2>&1) && fail "did not refuse \$HOME"

# 2. Clear error when docker is absent
(cd "$proj" && PATH="/usr/bin:/bin" "$cbox" 2>&1 || true) | grep -q "docker not found" \
  || fail "no 'docker not found' message"

# 3. Exact docker arguments
out="$(cd "$proj" && PATH="$fake:$PATH" "$cbox" --version)" || fail "cbox exited non-zero in a project dir"
expect() { grep -Fxq -- "$1" <<<"$out" || fail "missing docker arg: $1"; }
expect "run"
expect "--rm"
expect "-it"
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
```

- [ ] **Step 2: Run it and see it fail**

```bash
chmod +x test/cbox_test.sh && test/cbox_test.sh
```

Expected: `FAIL: no 'docker not found' message`, exit code 1. (Check 1 passes vacuously because the missing script fails to run; check 2 is the first one that inspects output.)

- [ ] **Step 3: Write `bin/cbox`**

```bash
#!/usr/bin/env bash
# Run Claude Code in a throwaway container that sees only $PWD and a persistent home volume.
set -euo pipefail

box="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"

command -v docker >/dev/null || { echo "cbox: docker not found — install OrbStack" >&2; exit 1; }
case "$PWD" in
  /|"$HOME") echo "cbox: refusing to mount $PWD — cd into a project first" >&2; exit 1 ;;
esac

exec docker run --rm -it \
  -v claude-dev-home:/home/dev \
  -v "$PWD:$PWD" \
  -v "$box/home/CLAUDE.md:/home/dev/.claude/CLAUDE.md:ro" \
  -w "$PWD" \
  claude-box claude "$@"
```

- [ ] **Step 4: Make it executable and run the test**

```bash
chmod +x bin/cbox && test/cbox_test.sh
```

Expected: `cbox_test OK`, exit 0.

- [ ] **Step 5: Install the symlink and confirm it resolves**

```bash
ln -sf "$HOME/repo/claude-box/bin/cbox" "$HOME/.local/bin/cbox"
cd /tmp && PATH="/usr/bin:/bin:$HOME/.local/bin" cbox; echo "exit=$?"
```

Expected: `cbox: docker not found — install OrbStack` and `exit=1`. This proves the symlink runs the script and `readlink -f` resolves it (the guard ran, so `$box` was computed without error).

---

### Task 3: Install a container runtime

**Files:** none

**Interfaces:**
- Consumes: nothing
- Produces: a working `docker` CLI on `PATH` for Tasks 4–6.

- [ ] **Step 1: Install OrbStack**

```bash
brew install --cask orbstack
open -a OrbStack
```

Finish OrbStack's first-launch prompts in the GUI. It installs the `docker` CLI and adds it to `PATH` for new shells.

- [ ] **Step 2: Verify from a fresh shell**

```bash
docker version --format '{{.Server.Os}}/{{.Server.Arch}}'
```

Expected: `linux/arm64`. If `docker: command not found`, open a new terminal window and retry; OrbStack's PATH entry only applies to shells started after install.

---

### Task 4: Dockerfile and image

**Files:**
- Create: `Dockerfile`
- Create: `test/smoke.sh`

**Interfaces:**
- Consumes: `home/settings.json`, `home/.gitconfig` (Task 1) via `COPY`.
- Produces: image `claude-box` with `claude`, `node`, `npm`, `mise`, `git`, `ps` on `PATH` for user `dev`; `/home/dev/.claude/` owned by `dev`; `DISABLE_AUTOUPDATER=1` in the environment.

- [ ] **Step 1: Write the failing smoke test `test/smoke.sh`**

This script runs *inside* the container.

```bash
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
[ "$(git config user.name)" = Your Name ]           || fail "git user.name is $(git config user.name)"
[ "$(git config user.email)" = you@example.com ] || fail "git user.email wrong"
node -e 'JSON.parse(require("fs").readFileSync(process.env.HOME+"/.claude/settings.json","utf8"))' \
                                               || fail "settings.json invalid"
echo "smoke OK"
```

- [ ] **Step 2: Run it and see it fail**

```bash
chmod +x test/smoke.sh
docker run --rm -v "$PWD/test/smoke.sh:/smoke.sh:ro" claude-box bash /smoke.sh
```

Expected: `Unable to find image 'claude-box:latest' locally` and a pull error. Exit code non-zero.

- [ ] **Step 3: Write `Dockerfile`**

```dockerfile
FROM debian:13-slim

# Base tools + Claude Code from Anthropic's signed apt repo (latest channel).
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl git procps \
 && install -d -m 0755 /etc/apt/keyrings \
 && curl -fsSL https://downloads.claude.ai/keys/claude-code.asc -o /etc/apt/keyrings/claude-code.asc \
 && echo "deb [signed-by=/etc/apt/keyrings/claude-code.asc] https://downloads.claude.ai/claude-code/apt/latest latest main" \
      > /etc/apt/sources.list.d/claude-code.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends claude-code \
 && rm -rf /var/lib/apt/lists/*

# mise binary in the image; its data dir stays under /home/dev so per-project Node versions persist in the volume.
ENV MISE_INSTALL_PATH=/usr/local/bin/mise
RUN curl -fsSL https://mise.run | sh

RUN useradd -m -u 1000 -s /bin/bash dev
USER dev
WORKDIR /home/dev
ENV PATH=/home/dev/.local/share/mise/shims:$PATH \
    DISABLE_AUTOUPDATER=1

# Global default Node. Lands in the volume on first run; project pins override via mise.
RUN mise use -g node@lts

# Seeded once into the volume. .claude/ must exist owned by dev before the CLAUDE.md bind mount lands inside it.
COPY --chown=dev:dev home/settings.json .claude/settings.json
COPY --chown=dev:dev home/.gitconfig .gitconfig
```

- [ ] **Step 4: Build**

```bash
docker build -t claude-box .
```

Expected: ends with `naming to docker.io/library/claude-box`. Takes a few minutes the first time (Node download).

Troubleshooting. The first row's fallback is from the setup docs; the other rows are untested guesses — try them only if the symptom appears:

| Symptom | Fix |
|---|---|
| `apt-get install claude-code` → `Unable to locate package` or arch error | apt repo may not serve arm64. Replace the `claude-code` apt lines with the native installer run as `dev` after `USER dev`: `RUN curl -fsSL https://claude.ai/install.sh \| bash` and add `/home/dev/.local/bin` to `ENV PATH`. Note in README that Claude Code then self-updates inside the volume. |
| `mise use -g node@lts` fails to extract | add `xz-utils` to the apt install line |
| `mise` prompts or hangs | prefix with `MISE_YES=1 ` |
| smoke test: `HOME is /` | add `ENV HOME=/home/dev` after `USER dev` |

- [ ] **Step 5: Run the smoke test**

```bash
docker run --rm -v "$PWD/test/smoke.sh:/smoke.sh:ro" claude-box bash /smoke.sh
```

Expected: version lines for claude, node, npm, mise, then `smoke OK`. Exit 0.

---

### Task 5: README

**Files:**
- Create: `README.md`

**Interfaces:**
- Consumes: commands from Tasks 2–4 verbatim.
- Produces: the only user-facing doc.

- [ ] **Step 1: Write `README.md`**

````markdown
# claude-box

Runs Claude Code in a throwaway Docker container that sees only the current directory and a persistent home volume. Makes auto mode safe to leave alone.

## Install

```bash
brew install --cask orbstack          # once; any Docker-compatible runtime works
docker build -t claude-box ~/repo/claude-box
ln -sf ~/repo/claude-box/bin/cbox ~/.local/bin/cbox
```

## Use

```bash
cd ~/repo/some-project
cbox                        # Claude Code, auto mode (your plan's default)
cbox --permission-mode plan # any claude flag passes through
cbox --resume
```

First run asks you to log in: open the printed URL on the Mac, paste the code back. That's stored in the volume; you won't be asked again.

## What the container sees

| Inside | Comes from | Writable |
|---|---|---|
| `$PWD` (same path as on the host) | your project, bind-mounted | yes |
| `/home/dev` | named volume `claude-dev-home` | yes |
| `/home/dev/.claude/CLAUDE.md` | `home/CLAUDE.md` in this repo | no |

Nothing else on the host exists inside. No `sudo`, no SSH keys, no published ports.

## Maintenance

| Task | Command |
|---|---|
| Update Claude Code / tools | `docker build --no-cache -t claude-box ~/repo/claude-box` |
| Edit global instructions | edit `home/CLAUDE.md`; next `cbox` picks it up |
| Add a system package | add it to the `apt-get install` line in `Dockerfile`, rebuild |
| Shell inside the volume | `docker run --rm -it -v claude-dev-home:/home/dev claude-box bash` |
| Reset the volume (logs you out, drops history and mise installs) | `docker volume rm claude-dev-home` |

`settings.json` and `.gitconfig` are copied into the volume only when it's first created. Rebuilding the image doesn't touch an existing volume; reset it to re-seed.

## Tests

```bash
test/cbox_test.sh                                                  # wrapper, no Docker needed
docker run --rm -v "$PWD/test/smoke.sh:/smoke.sh:ro" claude-box bash /smoke.sh   # image
```
````

- [ ] **Step 2: Verify every command in it exists**

```bash
grep -oE '(brew|docker|ln|cbox|test/cbox_test\.sh)[^`]*' README.md | sort -u
```

Read the list; each command must match one used in Tasks 2–4 or the spec. Expected: no command in the README that this plan didn't define.

---

### Task 6: First run and end-to-end verification

**Files:** none

**Interfaces:**
- Consumes: everything above.
- Produces: a logged-in, verified setup.

- [ ] **Step 1: Confirm the volume does not exist yet**

```bash
docker volume ls --filter name=claude-dev-home --format '{{.Name}}'
```

Expected: empty output. If it prints `claude-dev-home` from an earlier experiment, `docker volume rm claude-dev-home` first so the seeding path is exercised.

- [ ] **Step 2: First run and login**

```bash
cd ~/repo/claude-box && cbox
```

Claude Code starts, prints a login URL. Open it on the Mac, approve, paste the code at the prompt. Complete the onboarding prompts (theme etc.). Type `/status`.

Expected: `/status` shows the permission mode as auto and the working directory as `/Users/joeldickey/repo/claude-box`.

- [ ] **Step 3: Isolation checks, inside the same session**

Ask Claude to run each, or use the `!` prefix:

```bash
! ls /Users/joeldickey /Users/joeldickey/repo
! command -v sudo; echo "sudo exit=$?"
! node --version && npm --version
! cat ~/.claude/CLAUDE.md | head -3
! touch ~/.claude/CLAUDE.md; echo "touch exit=$?"
! ls -la ~/.claude/
```

Expected:

| Command | Expect |
|---|---|
| `ls /Users/joeldickey …` | only `repo`, and inside it only `claude-box` |
| `command -v sudo` | nothing; `sudo exit=1` |
| `node --version` | an LTS version |
| `cat ~/.claude/CLAUDE.md` | starts with `# Environment` |
| `touch ~/.claude/CLAUDE.md` | `Read-only file system`; `touch exit=1` |
| `ls -la ~/.claude/` | `.credentials.json`, `settings.json`, `CLAUDE.md`, all owned by `dev` |

- [ ] **Step 4: Persistence**

Exit Claude (`/exit`). Run `cbox` again in the same directory.

Expected: no login prompt; straight into a session.

- [ ] **Step 5: Per-project state is separate**

```bash
cd ~/repo/carta && cbox
```

Type `/resume`. Expected: no session from `claude-box` listed (or an empty list). Exit. Then:

```bash
cd ~/repo/claude-box && cbox
```

Type `/resume`. Expected: the session from Step 2 is listed. Exit.

- [ ] **Step 6: Wrapper guard against a real Docker**

```bash
cd ~ && cbox; echo "exit=$?"
```

Expected: `cbox: refusing to mount /Users/joeldickey — cd into a project first`, `exit=1`, and no container started (`docker ps -a --filter ancestor=claude-box` prints nothing).

- [ ] **Step 7: Volume seeding happened**

```bash
docker run --rm -v claude-dev-home:/home/dev claude-box bash -c 'git config user.name; ls ~/.local/share/mise/installs/node'
```

Expected: `Your Name` and one Node version directory — proof the image's `/home/dev` was copied into the volume on first creation.

---

## Amendment (2026-09-18, after Task 5)

Git identity moved out of the image into `.env` (see spec, "Git identity" decision and ".env" section). Net effect on the tasks above:

- Task 1: `home/.gitconfig` removed; the check's two `git config -f home/.gitconfig` lines no longer apply.
- Task 2: `bin/cbox` gained a `.env` guard and `--env-file "$box/.env"`; `test/cbox_test.sh` expects `--env-file` and `$box/.env`.
- Task 4: Dockerfile `COPY … .gitconfig` line removed; `test/smoke.sh` no longer checks `git config user.*`. Image rebuilt, smoke OK.
- Task 6 Step 7: `git config user.name` will print nothing — use `docker run --rm --env-file .env -v claude-dev-home:/home/dev claude-box git var GIT_AUTHOR_IDENT` instead.
- New files: `.env` (ignored), `.env.example`, `.gitignore`.
