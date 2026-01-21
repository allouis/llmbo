# llmbo

Run your agents in limbo.

Deploys Claude Code and OpenCode to any Linux machine with a single command.
No hardening, just reproducible environments on throwaway machines.

## Quickstart

    ./deploy.sh --host user@target

## How it works

llmbo uses Nix to install packages without touching the host OS. Everything lives in `/nix` and the home directory.

| File | What it does |
|------|--------------|
| `home.nix` | All configuration: packages, shell aliases, environment |
| `home/` | Files copied to `~/` on the target (add your dotfiles here) |
| `secrets.env` | API keys, copied to `~/.secrets.env` on target |

## Customizing

Edit `home.nix` to add packages or change settings. Run `./deploy.sh` again to apply.

Add files to `home/` and they'll appear in the target's home directory.

Put secrets in `secrets.env`:

    GH_TOKEN=ghp_xxx
    LINEAR_API_KEY=lin_api_xxx

## After deployment

SSH with agent forwarding and start a tmux session:

    ssh -A user@target
    tmux new -s work
    claude

To update packages on the target:

    update-agents   # just Claude Code + OpenCode
    update-system   # everything

`docker` commands use `podman` under the hood. Easier to set up, works the same.
