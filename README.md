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

## Security model

llmbo isolates agents on a separate machine. This protects your host system from damage - agents can't delete your files, install malware, or access local secrets like crypto wallets.

**What llmbo does NOT protect against:**

- **Credential exfiltration**: API tokens in `secrets.env` (GH_TOKEN, LINEAR_API_KEY) are exposed to agents and can be stolen
- **Token abuse**: Agents can use exposed tokens for unintended purposes (enumerate private repos, access your Linear data)
- **SSH agent abuse**: When you SSH with `-A`, agents can use your forwarded SSH keys to access any system you have access to

### Revoking SSH agent access

SSH agent forwarding is the biggest hole. Run `clear-forwarded-ssh` before starting agent work:

    ssh -A user@target     # login with agent forwarding
    # clone repos, set up workspace
    clear-forwarded-ssh               # remove the agent socket
    tmux new -s work       # new session has no SSH agent access
    claude                 # agent can't SSH to other machines

After `clear-forwarded-ssh`, agents can still push to already-cloned repos via HTTPS if GH_TOKEN is set.

### Recommendations for sensitive work

- Use [fine-grained GitHub PATs](https://github.com/settings/tokens?type=beta) scoped to specific repos
- Use read-only tokens when write access isn't needed
- Consider not forwarding SSH agent at all (`ssh` without `-A`)
- Treat the sandbox as semi-trusted, not fully isolated
