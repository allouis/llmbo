# llmbo

Run your agents in limbo.

Deploys Claude Code and OpenCode to any Linux machine with a single command.
No hardening, just reproducible environments on throwaway machines.

## Quickstart

    ./deploy.sh user@target              # home-manager (preserves OS)
    ./deploy.sh --nixos root@target      # nixos-anywhere (replaces OS)

## How it works

**Home-manager mode** (default): Uses Nix to install packages without touching the
host OS. Everything lives in `/nix` and the home directory.

**NixOS mode** (`--nixos`): Replaces the entire OS with NixOS via nixos-anywhere.
Use this for disposable remote servers where you want full control.

| File | What it does |
|------|--------------|
| `home-manager/home.nix` | Home-manager config: packages, shell, environment |
| `nixos/configuration.nix` | NixOS system config (for --nixos mode) |
| `shared/packages.nix` | Packages common to both modes |
| `home/` | Files copied to `~/` on the target |
| `secrets.env` | API keys, copied to `~/.secrets.env` on target |

## Customizing

Edit `home-manager/home.nix` (or `nixos/configuration.nix` for --nixos mode)
to add packages or change settings. Run `./deploy.sh` again to apply.

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

### Using a sandbox-only SSH key (recommended)

Instead of forwarding your SSH agent, generate a key that only exists on the sandbox:

    ssh user@target        # no -A flag
    sandbox-key            # generates key, shows public key
    # add the key to GitHub, GitLab, etc.

This key only exists on the sandbox. Add it wherever you need access. Agents can use it, but only for services you've explicitly added it to.

### Clearing forwarded SSH access

If you do use agent forwarding, run `clear-forwarded-ssh` before starting agent work:

    ssh -A user@target        # login with agent forwarding
    # clone repos, set up workspace
    clear-forwarded-ssh       # remove the forwarded key
    tmux new -s work          # new session has no SSH access
    claude                    # agent can't SSH to other machines

After `clear-forwarded-ssh`, agents can still push to already-cloned repos via HTTPS if GH_TOKEN is set.

### OrbStack users

OrbStack is designed for convenience, not isolation. It exposes your Mac's entire
filesystem, SSH agent, clipboard, and more to the VM. Run `isolate-orbstack` to
remove these integration points:

    isolate-orbstack

This unmounts Mac filesystem mounts, removes SSH agent access, and disables Mac
integration binaries. However, the agent has sudo and could potentially undo these
changes. For true isolation, use a real VM or cloud instance instead of OrbStack.

### Recommendations for sensitive work

- Use `sandbox-key` instead of SSH agent forwarding
- Use [fine-grained GitHub PATs](https://github.com/settings/tokens?type=beta) scoped to specific repos
- Use read-only tokens when write access isn't needed
- Treat the sandbox as semi-trusted, not fully isolated
