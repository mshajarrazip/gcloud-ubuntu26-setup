# GCP Ubuntu 26.04 LTS Setup

`setup.sh` provisions a fresh Google Cloud Ubuntu 26.04 LTS box with the tools
needed for day-to-day development. It is idempotent — every step checks for
existing state first, so the script is safe to re-run.

## What it installs

| Step     | Result |
|----------|--------|
| `apt`    | Base apt packages: `git`, `htop`, `tmux`, `ca-certificates`, `curl` |
| `uv`     | [uv](https://astral.sh/uv) (Astral), on `PATH` via `~/.local/bin` |
| `python` | CPython 3.12 via `uv python install` |
| `docker` | Docker CE from Docker's official apt repo, service enabled, current user added to the `docker` group |
| `sshkey` | An ed25519 SSH key at `~/.ssh/id_ed25519` (only if none exists), then prints the public key |

## Usage

```bash
./setup.sh                 # run every step
./setup.sh docker uv       # run only the named steps
```

Run it as your normal user, not root — it calls `sudo` itself where needed.

## Notes

- After the `docker` step, log out and back in (or run `newgrp docker`) before
  running `docker` without `sudo`.
- The `python` step requires `uv`; run the `uv` step first if you invoke steps
  individually.
