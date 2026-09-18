# claude-box

Runs Claude Code in a throwaway Docker container with host filesystem access limited to the project and the mounts listed below.

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

The wrapper does not mount your host home directory, SSH agent, or Docker socket. No `sudo` or explicitly published ports. Files already inside the project remain accessible.

Git identity comes from `.env` (`GIT_AUTHOR_*` / `GIT_COMMITTER_*`), passed as environment variables via `--env-file`. The file itself is never mounted and is git-ignored.

## Limitations

- The project is writable, including any secrets it contains. Container isolation does not prevent file deletion or uploading accessible data.
- Networking is unrestricted: internet, reachable Mac services, LAN/VPN destinations, and containers on the same bridge. No published ports does not mean network isolation.
- All projects share the persistent home, including Claude credentials, history, settings, and installed tools. Changes there survive container removal.
- The wrapper requires an interactive terminal; piped input and unattended scripts are not supported yet.

## Possible future improvements

- Optional firewall blocking local/private networks while preserving public internet access.
- Separate home volumes per project or trust boundary.
- Non-interactive runs and automatic support for `.node-version` pins.

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
