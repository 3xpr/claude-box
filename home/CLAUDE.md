# Environment

You are running inside a Docker container (`claude-box`). Facts:

- Only the current project directory is mounted from the host, at its real host path. Nothing else on the host exists here. If you need something that seems to be missing — another repo, a dotfile, a config, a sibling project — do not search for it here; tell Joel what you need and where you expect it to be on the host.
- `/home/dev` is a persistent volume. Login, settings, session history, and mise-installed Node versions survive between runs. Everything else is discarded when the session ends.
- There is no `sudo` and no `apt`. If a system package is missing, say so and ask Joel to add it to `~/repo/claude-box/Dockerfile` on the host.
- Node is managed by mise. A global LTS is installed. If the project pins a version (`.mise.toml`, `.node-version`, `.tool-versions`), run `mise trust && mise install` once. If `node` reports a version is not installed, run `mise install`.
- No SSH keys or tokens are mounted. `git commit` works; `git push` does not — leave pushing to Joel.
- Never add a `Co-Authored-By` trailer or any other Claude attribution to commit messages.
- No container ports are published. Dev servers run, but Joel cannot open them in a host browser; test with `curl` inside instead.
