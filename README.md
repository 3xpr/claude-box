# claude-box

Runs Claude Code in a throwaway Docker container that sees only the current directory and a persistent home volume. Makes auto mode safe to leave alone.

## Install

```bash
brew install --cask orbstack          # once; any Docker-compatible runtime works
docker build -t claude-box ~/repo/claude-box
ln -sf ~/repo/claude-box/bin/cbox ~/.local/bin/cbox
cp ~/repo/claude-box/.env.example ~/repo/claude-box/.env   # then fill in your git name/email
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

Git identity comes from `.env` (`GIT_AUTHOR_*` / `GIT_COMMITTER_*`), passed as environment variables via `--env-file`. The file itself is never mounted and is git-ignored.

## Maintenance

| Task | Command |
|---|---|
| Update Claude Code / tools | `docker build --no-cache -t claude-box ~/repo/claude-box` |
| Edit global instructions | edit `home/CLAUDE.md`; next `cbox` picks it up |
| Add a system package | add it to the `apt-get install` line in `Dockerfile`, rebuild |
| Shell inside the volume | `docker run --rm -it -v claude-dev-home:/home/dev claude-box bash` |
| Reset the volume (logs you out, drops history and mise installs) | `docker volume rm claude-dev-home` |

`settings.json` is copied into the volume only when it's first created. Rebuilding the image doesn't touch an existing volume; reset it to re-seed.

## Tests

```bash
test/cbox_test.sh                                                  # wrapper, no Docker needed
docker run --rm -v "$PWD/test/smoke.sh:/smoke.sh:ro" claude-box bash /smoke.sh   # image
```
