# claude-box design

Isolate Claude Code to the current directory so auto mode is safe to leave unattended.

## Goal

A wrapper `cbox` that runs Claude Code inside a throwaway Docker container. The container sees exactly two things from the host: the directory `cbox` was launched from, and a persistent named volume holding Claude Code's own state. Nothing else on the host exists inside.

## Decisions already made

| Decision | Choice | Why |
|---|---|---|
| Mount path | `$PWD` mounted at the same absolute path inside (`-v "$PWD:$PWD" -w "$PWD"`) | Claude Code keys per-project state by absolute path (`~/.claude/projects/<path>/`, `~/.claude.json`). A fixed `/workspace` would collapse every project into one history/memory bucket. Isolation is identical either way. |
| Claude Code install | apt repository, `latest` channel, into the image; `DISABLE_AUTOUPDATER=1` | Image = tools, volume = state. Update by rebuilding. |
| Node | mise, global default `node@lts`, shims on `PATH` | Per-project `.mise.toml` / `.node-version` override automatically. Shims work in Claude's non-interactive Bash tool where `mise activate` would not. |
| User | non-root `dev`, uid 1000 | Bypass mode is refused as root; docs recommend non-root. macOS runtimes map bind-mount ownership transparently. |
| Auth | OAuth login once inside the container | Credentials and `~/.claude.json` both live under `/home/dev`, which is the volume, so they persist. No host credential files are mounted. |
| Permission mode | none set | Auto mode is the built-in default on Pro/Max. `cbox --permission-mode X` passes through when wanted. |
| Extra packages | `procps` only, beyond `ca-certificates curl git` | Claude uses `ps`/`pkill` to manage dev servers it starts. Everything else the reference devcontainer installs is for TTY use or its firewall. |
| Git identity | `.env` at the repo root, passed with `docker run --env-file`; git-ignored, `.env.example` tracked | Keeps name/email out of the repo and out of the image. Git reads `GIT_AUTHOR_*` / `GIT_COMMITTER_*` directly, so no `.gitconfig` and no mapping code. |
| Container runtime | OrbStack (user installs) | None present on the host today. Docker Desktop or Colima work identically. |

## Layout

```
~/repo/claude-box/           git repo
├── Dockerfile
├── README.md                build, first run, emergency shell one-liner
├── .env                     git identity (GIT_AUTHOR_*/GIT_COMMITTER_*); git-ignored
├── .env.example             same keys, placeholder values
├── .gitignore               .env, .superpowers/
├── bin/cbox                 wrapper; symlink → ~/.local/bin/cbox
├── home/
│   ├── CLAUDE.md            bind-mounted read-only into /home/dev/.claude/CLAUDE.md on every run
│   └── settings.json        COPY'd into the image; lands in the volume on first run
└── docs/superpowers/specs/  this file
```

Two seeding mechanisms on purpose:

- `CLAUDE.md` is bind-mounted `:ro` each run so it is edited on the host, is always current, and Claude cannot rewrite its own rules.
- `settings.json` rides Docker's first-run volume population (a named volume mounted over a non-empty image path is populated from the image once, when the volume is empty). Claude Code must be able to write `settings.json` (plugin installs, `/config`), so it cannot be read-only.

Consequence: rebuilding the image does not update files already in the volume. To re-seed, `docker volume rm claude-dev-home` (loses login, history, mise installs). Documented in README.

## Dockerfile

```dockerfile
FROM debian:13-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl git procps \
 && install -d -m 0755 /etc/apt/keyrings \
 && curl -fsSL https://downloads.claude.ai/keys/claude-code.asc -o /etc/apt/keyrings/claude-code.asc \
 && echo "deb [signed-by=/etc/apt/keyrings/claude-code.asc] https://downloads.claude.ai/claude-code/apt/latest latest main" \
      > /etc/apt/sources.list.d/claude-code.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends claude-code \
 && rm -rf /var/lib/apt/lists/*

ENV MISE_INSTALL_PATH=/usr/local/bin/mise
RUN curl -fsSL https://mise.run | sh

RUN useradd -m -u 1000 -s /bin/bash dev
USER dev
WORKDIR /home/dev
ENV PATH=/home/dev/.local/share/mise/shims:$PATH \
    DISABLE_AUTOUPDATER=1

RUN mise use -g node@lts
COPY --chown=dev:dev home/settings.json .claude/settings.json
```

Notes:

- `.claude/` is created by the `COPY`, owned by `dev`, before any bind mount lands inside it. This matters: if Docker had to create `.claude/` itself to host the `CLAUDE.md` file mount, it would be root-owned and Claude Code could not write credentials next to it.
- Host is arm64; the apt repo must serve `linux-arm64`. Verify at first build; fallback is the native installer (`curl -fsSL https://claude.ai/install.sh | bash`) run as `dev`, which then lives in the volume.
- No `sudo`. Anything Claude cannot install is added to this file by the user.

## Wrapper `bin/cbox`

```bash
#!/usr/bin/env bash
set -euo pipefail

box="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"

command -v docker >/dev/null || { echo "cbox: docker not found — install OrbStack" >&2; exit 1; }
project="$(pwd -P)"
user_home="$(cd -- "$HOME" && pwd -P)"
case "$project" in
  /|"$user_home"|"$box"|"$box"/*)
    echo "cbox: refusing to mount $project — cd into a project first" >&2
    exit 1
    ;;
esac
[ -f "$box/.env" ] || { echo "cbox: $box/.env missing — cp .env.example .env and fill in your git identity" >&2; exit 1; }

exec docker run --rm -it \
  --env-file "$box/.env" \
  -v claude-dev-home:/home/dev \
  -v "$project:$project" \
  -v "$box/home/CLAUDE.md:/home/dev/.claude/CLAUDE.md:ro" \
  -w "$project" \
  claude-box claude "$@"
```

- All arguments pass through to `claude`, so `cbox --permission-mode plan`, `cbox -p "..."`, `cbox --resume` work.
- Four guards: docker present; the physical path (`pwd -P`, so a symlink can't dodge it) is not `/`, `$HOME`, or inside the claude-box repo itself (a mounted `bin/cbox` would be Claude-writable and runs on the host — develop claude-box with host Claude Code); `.env` exists (without it git inside reports `Author identity unknown`).
- `--env-file` reads `.env` on the host and injects its lines as environment variables; the file is never mounted.
- No `shell` subcommand. README documents the emergency one-liner:
  `docker run --rm -it -v claude-dev-home:/home/dev claude-box bash`

## home/CLAUDE.md

Content, verbatim:

```markdown
# Environment

You are running inside a Docker container (`claude-box`). Facts:

- Only the current project directory is mounted from the host, at its real host path. Nothing else on the host exists here. If you need something that seems to be missing — another repo, a dotfile, a config, a sibling project — do not search for it here; tell Joel what you need and where you expect it to be on the host.
- `/home/dev` is a persistent volume. Login, settings, session history, and mise-installed Node versions survive between runs. Everything else is discarded when the session ends.
- There is no `sudo` and no `apt`. If a system package is missing, say so and ask Joel to add it to `~/repo/claude-box/Dockerfile` on the host.
- Node is managed by mise. A global LTS is installed. If the project pins a version (`.mise.toml`, `.node-version`, `.tool-versions`), run `mise trust && mise install` once. If `node` reports a version is not installed, run `mise install`.
- No SSH keys or tokens are mounted. `git commit` works; `git push` does not — leave pushing to Joel.
- Never add a `Co-Authored-By` trailer or any other Claude attribution to commit messages.
- No container ports are published. Dev servers run, but Joel cannot open them in a host browser; test with `curl` inside instead.
```

## home/settings.json

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

Format mirrors the host's existing `autoMode.environment` block (array of markdown strings).

## .env

```ini
GIT_AUTHOR_NAME=Your Name
GIT_AUTHOR_EMAIL=you@example.com
GIT_COMMITTER_NAME=Your Name
GIT_COMMITTER_EMAIL=you@example.com
```

Four variables, not two: git needs both author and committer, otherwise it invents `dev@<container-id>` for the committer and warns on every commit. `.env.example` carries the same keys with placeholder values. `.gitignore` lists `.env` and `.superpowers/`.

## First run

1. Install OrbStack.
2. `docker build -t claude-box ~/repo/claude-box`
3. `ln -s ~/repo/claude-box/bin/cbox ~/.local/bin/cbox`
4. `cp .env.example .env` and fill in name/email.
5. `cd` into any project, run `cbox`. Claude Code prints a login URL; open it on the host; paste the code back when prompted (the localhost callback does not reach the container). Credentials persist in the volume.

## Verification

Docker is not installed on the host at design time, so these run after step 1:

| Check | Command | Expect |
|---|---|---|
| Binary | `cbox --version` | a version string |
| Isolation | inside a session: `ls /Users/joeldickey` | only the one project directory |
| Node | inside: `node --version && npm --version` | LTS versions |
| No escalation | inside: `command -v sudo` | nothing |
| Rules mounted | inside: `cat ~/.claude/CLAUDE.md` | the file above; `touch` it fails (read-only) |
| Auto mode | `/status` | permission mode auto |
| Persistence | exit, `cbox` again | no login prompt |
| Per-project state | run from two different projects, `/resume` in each | separate histories |
| Guard | `cd ~ && cbox` | refuses |

## Out of scope

Egress firewall, publishing ports, git push from inside, Linux-host uid mapping, project-specific system packages. Each is a one-line addition when wanted.

## Sources

- https://code.claude.com/docs/en/setup — install methods, apt repo, `DISABLE_AUTOUPDATER`
- https://code.claude.com/docs/en/devcontainer — persistence of `~/.claude` and `~/.claude.json`, non-root requirement, do-not-mount-secrets warning
- https://code.claude.com/docs/en/permission-modes — auto mode default, `--permission-mode` flag
- https://mise.jdx.dev/installing-mise.html — Docker install pattern
- https://github.com/anthropics/claude-code/blob/main/.devcontainer/Dockerfile — reference package list
