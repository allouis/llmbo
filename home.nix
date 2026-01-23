# Home Manager configuration for LLM agent machines
{ config, pkgs, lib, llmPkgs, ... }:

{
  home.stateVersion = "24.11";

  home.packages = with pkgs; [
    # LLM agents
    llmPkgs.claude-code
    llmPkgs.opencode

    # Version control
    git
    jujutsu
    gh

    # Editor
    vim

    # Tools
    ripgrep
    fd
    tree
    jq
    curl
    wget
    htop

    # Node.js
    nodejs_22  # LTS
    yarn

    # Containers (podman as rootless docker replacement)
    podman
    podman-compose
  ];

  # Rootless podman config
  xdg.configFile."containers/policy.json".text = builtins.toJSON {
    default = [{ type = "insecureAcceptAnything"; }];
  };

  xdg.configFile."containers/registries.conf".text = ''
    [registries.search]
    registries = ['docker.io']
  '';

  home.sessionPath = [ "$HOME/bin" ];

  home.sessionVariables = {
    EDITOR = "vim";
    IS_SANDBOX = "1";
  };

  # SSH agent socket persistence for tmux
  # When you SSH with -A, the agent socket path is session-specific.
  # This creates a stable symlink that tmux sessions can use.
  programs.bash = {
    enable = true;
    shellAliases = {
      docker = "podman";
      docker-compose = "podman-compose";
    };
    initExtra = ''
      # Load secrets if present
      if [ -f "$HOME/.secrets.env" ]; then
        set -a
        source "$HOME/.secrets.env"
        set +a
      fi

      # Update agent socket symlink on new SSH connections with -A
      # Standard SSH forwarding uses /tmp/ssh-XXX/agent.XXX
      if [[ "$SSH_AUTH_SOCK" == /tmp/ssh-*/agent.* ]]; then
        mkdir -p "$HOME/.ssh"
        ln -sf "$SSH_AUTH_SOCK" "$HOME/.ssh/agent_socket"
        export SSH_AUTH_SOCK="$HOME/.ssh/agent_socket"
      fi

      # Use compatible TERM for remote sessions (kitty/alacritty terminfo often missing)
      case "$TERM" in
        xterm-kitty|alacritty) export TERM=xterm-256color ;;
      esac

      # Show welcome banner on interactive login
      if [[ $- == *i* ]] && [[ -z "$AGENT_BANNER_SHOWN" ]]; then
        export AGENT_BANNER_SHOWN=1
        echo ""
        echo "  Welcome to llmbo"
        echo ""
        echo -e "  \e[1mclaude\e[0m                 Claude Code $(claude --version 2>/dev/null | cut -d' ' -f1)"
        echo -e "  \e[1mopencode\e[0m               OpenCode $(opencode --version 2>/dev/null | head -1 || echo "")"
        echo -e "  \e[1mupdate-agents\e[0m          Update agents to latest"
        echo -e "  \e[1mupdate-system\e[0m          Update all packages"
        echo -e "  \e[1msandbox-key\e[0m            Get SSH key for this machine"
        echo ""
        echo -e "  \e[1mtmux new -s work\e[0m       Start persistent session"
        echo -e "  \e[1mtmux attach\e[0m            Reconnect to session"
        echo ""
        echo -e "  \e[2mdocker is aliased to podman (rootless)\e[0m"
        echo ""

        # Note about SSH key forwarding (check if agent is actually accessible)
        if ssh-add -l &>/dev/null; then
          echo -e "  \e[33mSSH key forwarding active.\e[0m"
          echo -e "  \e[2mGood for cloning repos, but it goes away when you disconnect.\e[0m"
          if [[ "$SSH_AUTH_SOCK" == *orbstack* ]]; then
            echo -e "  \e[2mOrbStack always forwards your SSH keys.\e[0m"
          fi
          echo -e "  \e[2mRun \e[0msandbox-key\e[2m to generate a permanent key for this machine.\e[0m"
          echo -e "  \e[2mRun \e[0mclear-forwarded-ssh\e[2m to remove access to your forwarded keys.\e[0m"
          echo ""
        fi
      fi
    '';
  };

  # tmux config to update environment on attach
  programs.tmux = {
    enable = true;
    extraConfig = ''
      set -g update-environment "SSH_AUTH_SOCK"
    '';
  };

  # Direnv for project-specific environments
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;  # Better nix integration, caches devshells
    config.whitelist.prefix = [ "/" ];  # Auto-allow all directories (sandbox environment)
  };

  # Let home-manager manage itself
  programs.home-manager.enable = true;
}
