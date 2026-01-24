#!/usr/bin/env bash
set -euo pipefail

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# --- Error handling ---
trap 'echo -e "${RED}Deployment failed at line $LINENO${NC}" >&2' ERR

# --- State ---
TARGET_HOST=""
ARCH=""
GH_TOKEN=""
LINEAR_API_KEY=""
CONTEXT7_API_KEY=""
GIT_USER_NAME=""
GIT_USER_EMAIL=""

# --- Argument parsing ---
usage() {
  cat <<EOF
llmbo — put your LLM agents in limbo

Installs Nix and configures LLM agent tools on a remote machine.

Options:
  -H, --host HOST        Target host (e.g., root@192.168.1.100)
  -t, --gh-token TOKEN   GitHub personal access token
      --linear-key KEY   Linear API key (for issue tracking MCP)
      --context7-key KEY Context7 API key (for docs lookup MCP)
  -h, --help             Show this help message

Examples:
  $(basename "$0")                        # Interactive mode
  $(basename "$0") --host nixos@myvm      # Non-interactive, skip API keys
  $(basename "$0") -H user@host -t TOKEN  # Fully automated
EOF
  exit 0
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      -H|--host)
        [[ -z "${2:-}" || "$2" == -* ]] && error "--host requires a value"
        TARGET_HOST="$2"
        HOST_FROM_FLAG=1
        shift 2
        ;;
      -t|--gh-token)
        [[ -z "${2:-}" || "$2" == -* ]] && error "--gh-token requires a value"
        GH_TOKEN="$2"
        shift 2
        ;;
      --linear-key)
        [[ -z "${2:-}" || "$2" == -* ]] && error "--linear-key requires a value"
        LINEAR_API_KEY="$2"
        shift 2
        ;;
      --context7-key)
        [[ -z "${2:-}" || "$2" == -* ]] && error "--context7-key requires a value"
        CONTEXT7_API_KEY="$2"
        shift 2
        ;;
      -h|--help)
        usage
        ;;
      *)
        error "Unknown option: $1"
        ;;
    esac
  done
}

# --- Helper functions ---
info() {
  echo -e "${BLUE}$1${NC}"
}

success() {
  echo -e "${GREEN}$1${NC}"
}

error() {
  echo -e "${RED}$1${NC}" >&2
  exit 1
}

# Get max lastModified timestamp from a flake.lock file
get_flake_max_timestamp() {
  local lock_file="$1"
  jq '[.nodes[].locked.lastModified // 0] | max' "$lock_file" 2>/dev/null || echo 0
}

# --- Main functions ---
print_header() {
  echo ""
  echo -e "${BOLD}Welcome to llmbo${NC}"
  echo ""
  echo "This will install Nix and LLM agent tools on the target machine."
  echo "The host OS is preserved — only Nix and home-manager are added."
  echo ""
}

prompt_target_host() {
  if [[ -n "$TARGET_HOST" ]]; then
    return
  fi

  read -rp "Target host (e.g., root@192.168.1.100): " TARGET_HOST

  if [[ -z "$TARGET_HOST" ]]; then
    error "Target host cannot be empty"
  fi

  echo ""
}

detect_system() {
  echo -n "Detecting system... "

  if ! ARCH=$(ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new "$TARGET_HOST" "uname -m" 2>/dev/null); then
    echo ""
    error "Could not connect to $TARGET_HOST. Check the address and SSH access."
  fi

  case "$ARCH" in
    x86_64) ARCH="x86_64-linux" ;;
    aarch64) ARCH="aarch64-linux" ;;
    *)
      echo ""
      error "Unsupported architecture: $ARCH"
      ;;
  esac

  success "$ARCH"
  echo ""
}

detect_api_keys() {
  # Try to detect API keys from local environment and config files

  # GitHub: check GST_TOKEN, then GH_TOKEN
  if [[ -z "$GH_TOKEN" ]]; then
    if [[ -n "${GST_TOKEN:-}" ]]; then
      GH_TOKEN="$GST_TOKEN"
      GH_TOKEN_SOURCE="GST_TOKEN env"
    elif [[ -n "${GH_TOKEN:-}" ]]; then
      GH_TOKEN_SOURCE="GH_TOKEN env"
    fi
  fi

  # Linear: check env, then Claude MCP config
  if [[ -z "$LINEAR_API_KEY" ]]; then
    if [[ -n "${LINEAR_API_KEY:-}" ]]; then
      LINEAR_KEY_SOURCE="LINEAR_API_KEY env"
    elif [[ -f "$HOME/.claude.json" ]]; then
      local key
      key=$(jq -r '.mcpServers.linear.env.LINEAR_API_KEY // empty' "$HOME/.claude.json" 2>/dev/null)
      if [[ -n "$key" ]]; then
        LINEAR_API_KEY="$key"
        LINEAR_KEY_SOURCE="Claude MCP config"
      fi
    fi
  fi

  # Context7: check env, then Claude MCP config
  if [[ -z "$CONTEXT7_API_KEY" ]]; then
    if [[ -n "${CONTEXT7_API_KEY:-}" ]]; then
      CONTEXT7_KEY_SOURCE="CONTEXT7_API_KEY env"
    elif [[ -f "$HOME/.claude.json" ]]; then
      local key
      key=$(jq -r '.mcpServers.context7.env.CONTEXT7_API_KEY // empty' "$HOME/.claude.json" 2>/dev/null)
      if [[ -n "$key" ]]; then
        CONTEXT7_API_KEY="$key"
        CONTEXT7_KEY_SOURCE="Claude MCP config"
      fi
    fi
  fi
}

detect_git_identity() {
  # Try to detect git identity from local git config
  if [[ -z "$GIT_USER_NAME" ]]; then
    local name
    name=$(git config user.name 2>/dev/null || true)
    if [[ -n "$name" ]]; then
      GIT_USER_NAME="$name"
      GIT_NAME_SOURCE="local git config"
    fi
  fi

  if [[ -z "$GIT_USER_EMAIL" ]]; then
    local email
    email=$(git config user.email 2>/dev/null || true)
    if [[ -n "$email" ]]; then
      GIT_USER_EMAIL="$email"
      GIT_EMAIL_SOURCE="local git config"
    fi
  fi
}

prompt_git_identity() {
  # Skip all prompts in non-interactive mode (host was passed via flag)
  if [[ -n "${HOST_FROM_FLAG:-}" ]]; then
    return
  fi

  # Git identity
  if [[ -n "$GIT_USER_NAME" && -n "$GIT_USER_EMAIL" ]]; then
    echo "Git identity detected from ${GIT_NAME_SOURCE:-config}:"
    echo "  Name:  $GIT_USER_NAME"
    echo "  Email: $GIT_USER_EMAIL"
    read -rp "Use this identity? [Y/n]: " confirm
    if [[ "$confirm" =~ ^[Nn] ]]; then
      GIT_USER_NAME=""
      GIT_USER_EMAIL=""
    fi
    echo ""
  fi

  if [[ -z "$GIT_USER_NAME" || -z "$GIT_USER_EMAIL" ]]; then
    echo "Git identity (optional)"
    echo ""
    echo "Configure git author for commits made on the remote."
    echo ""
    if [[ -z "$GIT_USER_NAME" ]]; then
      read -rp "Name (or press Enter to skip): " GIT_USER_NAME
    fi
    if [[ -n "$GIT_USER_NAME" && -z "$GIT_USER_EMAIL" ]]; then
      read -rp "Email: " GIT_USER_EMAIL
    fi
    echo ""
  fi
}

prompt_api_keys() {
  # Skip all prompts in non-interactive mode (host was passed via flag)
  if [[ -n "${HOST_FROM_FLAG:-}" ]]; then
    return
  fi

  # Try to auto-detect keys first
  detect_api_keys

  # GitHub token
  if [[ -n "$GH_TOKEN" && -n "${GH_TOKEN_SOURCE:-}" ]]; then
    echo "GitHub token detected from $GH_TOKEN_SOURCE"
    read -rp "Use this token? [Y/n]: " confirm
    if [[ "$confirm" =~ ^[Nn] ]]; then
      GH_TOKEN=""
    fi
    echo ""
  fi
  if [[ -z "$GH_TOKEN" ]]; then
    echo "GitHub CLI authentication (optional)"
    echo ""
    echo "To enable 'gh' commands, provide a Personal Access Token."
    echo "Agents will have full access to this token."
    echo "Consider using a fine-grained PAT: https://github.com/settings/tokens?type=beta"
    echo ""
    read -rsp "GitHub token (or press Enter to skip): " GH_TOKEN
    echo ""
    echo ""
  fi

  # Linear API key
  if [[ -n "$LINEAR_API_KEY" && -n "${LINEAR_KEY_SOURCE:-}" ]]; then
    echo "Linear API key detected from $LINEAR_KEY_SOURCE"
    read -rp "Use this key? [Y/n]: " confirm
    if [[ "$confirm" =~ ^[Nn] ]]; then
      LINEAR_API_KEY=""
    fi
    echo ""
  fi
  if [[ -z "$LINEAR_API_KEY" ]]; then
    echo "Linear MCP (optional)"
    echo ""
    echo "To enable issue tracking via Linear MCP, provide an API key."
    echo "Agents will have full access to this token."
    echo "Create one at: https://linear.app/settings/api"
    echo ""
    read -rsp "Linear API key (or press Enter to skip): " LINEAR_API_KEY
    echo ""
    echo ""
  fi

  # Context7 API key
  if [[ -n "$CONTEXT7_API_KEY" && -n "${CONTEXT7_KEY_SOURCE:-}" ]]; then
    echo "Context7 API key detected from $CONTEXT7_KEY_SOURCE"
    read -rp "Use this key? [Y/n]: " confirm
    if [[ "$confirm" =~ ^[Nn] ]]; then
      CONTEXT7_API_KEY=""
    fi
    echo ""
  fi
  if [[ -z "$CONTEXT7_API_KEY" ]]; then
    echo "Context7 MCP (optional)"
    echo ""
    echo "To enable docs lookup via Context7 MCP, provide an API key."
    echo "Agents will have full access to this token."
    echo "Create one at: https://context7.com/settings"
    echo ""
    read -rsp "Context7 API key (or press Enter to skip): " CONTEXT7_API_KEY
    echo ""
    echo ""
  fi
}

install_nix() {
  info "Checking Nix installation..."

  local nix_installed
  nix_installed=$(ssh "$TARGET_HOST" "command -v nix >/dev/null 2>&1 && echo yes || echo no")

  if [[ "$nix_installed" == "yes" ]]; then
    success "Nix already installed"
  else
    info "Installing Nix via Determinate Systems installer..."
    ssh "$TARGET_HOST" "curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm"
    success "Nix installed"
  fi

  # Configure binary cache and trusted users
  info "Configuring Nix daemon..."
  ssh "$TARGET_HOST" '
    # On NixOS, /etc/nix/nix.conf is a symlink to the store - replace with real file
    if [ -L /etc/nix/nix.conf ]; then
      sudo cp --remove-destination $(readlink -f /etc/nix/nix.conf) /etc/nix/nix.conf
    fi
    # Add current user to trusted-users (needed for binary cache)
    if ! grep -qE "^trusted-users.*\b$USER\b" /etc/nix/nix.conf 2>/dev/null; then
      echo "trusted-users = root $USER" | sudo tee -a /etc/nix/nix.conf
    fi
    # Add binary cache
    if ! grep -q "cache.numtide.com" /etc/nix/nix.conf 2>/dev/null; then
      echo "extra-substituters = https://cache.numtide.com" | sudo tee -a /etc/nix/nix.conf
      echo "extra-trusted-public-keys = niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=" | sudo tee -a /etc/nix/nix.conf
    fi
    sudo systemctl restart nix-daemon 2>/dev/null || true
  '

  echo ""
}

setup_config() {
  info "Setting up configuration..."

  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local remote_home
  remote_home=$(ssh "$TARGET_HOST" "echo \$HOME")

  # Copy flake files
  ssh "$TARGET_HOST" "mkdir -p '$remote_home/.config/home-manager'"

  # Always copy flake.nix and home.nix
  scp -q "$script_dir"/{flake.nix,home.nix} "$TARGET_HOST:$remote_home/.config/home-manager/"

  # Smart sync for flake.lock - only push if local is newer
  local local_ts remote_lock remote_ts
  local_ts=$(get_flake_max_timestamp "$script_dir/flake.lock")
  remote_lock="$remote_home/.config/home-manager/flake.lock"
  remote_ts=$(ssh "$TARGET_HOST" "cat '$remote_lock' 2>/dev/null" | get_flake_max_timestamp /dev/stdin || echo 0)

  if [[ "$local_ts" -gt "$remote_ts" ]]; then
    scp -q "$script_dir/flake.lock" "$TARGET_HOST:$remote_home/.config/home-manager/"
    info "Pushed local flake.lock (newer than remote)"
  elif [[ "$remote_ts" -gt "$local_ts" ]]; then
    info "Keeping remote flake.lock (newer than local)"
  else
    info "flake.lock versions match"
  fi

  # Secrets file (if exists locally)
  if [[ -f "$script_dir/secrets.env" ]]; then
    scp -q "$script_dir/secrets.env" "$TARGET_HOST:$remote_home/.secrets.env"
  fi

  # Append API keys to secrets (if provided)
  if [[ -n "$GH_TOKEN" ]]; then
    ssh "$TARGET_HOST" "echo 'GH_TOKEN=$GH_TOKEN' >> '$remote_home/.secrets.env'"
  fi
  if [[ -n "$LINEAR_API_KEY" ]]; then
    ssh "$TARGET_HOST" "echo 'LINEAR_API_KEY=$LINEAR_API_KEY' >> '$remote_home/.secrets.env'"
  fi
  if [[ -n "$CONTEXT7_API_KEY" ]]; then
    ssh "$TARGET_HOST" "echo 'CONTEXT7_API_KEY=$CONTEXT7_API_KEY' >> '$remote_home/.secrets.env'"
  fi

  # Append git identity to secrets (if provided)
  # Using GIT_AUTHOR_* and GIT_COMMITTER_* env vars which git uses automatically
  # Values are double-quoted in the file so apostrophes don't break sourcing
  # Piping avoids shell quoting issues with special characters in names
  if [[ -n "$GIT_USER_NAME" ]]; then
    printf 'GIT_AUTHOR_NAME="%s"\nGIT_COMMITTER_NAME="%s"\n' "$GIT_USER_NAME" "$GIT_USER_NAME" | \
      ssh "$TARGET_HOST" "cat >> '$remote_home/.secrets.env'"
  fi
  if [[ -n "$GIT_USER_EMAIL" ]]; then
    printf 'GIT_AUTHOR_EMAIL="%s"\nGIT_COMMITTER_EMAIL="%s"\n' "$GIT_USER_EMAIL" "$GIT_USER_EMAIL" | \
      ssh "$TARGET_HOST" "cat >> '$remote_home/.secrets.env'"
  fi

  # Ensure secrets file has correct permissions
  ssh "$TARGET_HOST" "[ -f '$remote_home/.secrets.env' ] && chmod 600 '$remote_home/.secrets.env'" || true

  # Home directory files (excluding README)
  if [[ -d "$script_dir/home" ]]; then
    if ssh "$TARGET_HOST" "command -v rsync" >/dev/null 2>&1; then
      rsync -aq --no-owner --no-group --exclude='README.md' "$script_dir/home/" "$TARGET_HOST:$remote_home/"
    else
      # Fallback: scp everything then remove README
      scp -rq "$script_dir/home/." "$TARGET_HOST:$remote_home/"
      ssh "$TARGET_HOST" "rm -f '$remote_home/README.md'"
    fi
  fi

  success "Configuration copied"
  echo ""
}

setup_swap() {
  # Skip on NixOS - swap should be configured declaratively in NixOS config
  if ssh "$TARGET_HOST" "[ -f /etc/NIXOS ]" 2>/dev/null; then
    info "NixOS detected, skipping swap setup"
    echo ""
    return
  fi

  info "Ensuring swap is configured..."
  ssh "$TARGET_HOST" "
    if [ ! -f /swapfile ]; then
      fallocate -l 4G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=4096 2>/dev/null
      chmod 600 /swapfile
      mkswap /swapfile >/dev/null
      swapon /swapfile 2>/dev/null || true
      # Try to persist across reboots (may fail on some systems)
      if [ -w /etc/fstab ] && ! grep -q /swapfile /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
      fi
    elif ! swapon --show | grep -q /swapfile; then
      swapon /swapfile 2>/dev/null || true
    fi
  "
  echo ""
}

setup_podman() {
  info "Configuring rootless containers..."
  ssh "$TARGET_HOST" '
    # Add subuid/subgid for current user (needed for rootless podman)
    if ! grep -q "^$USER:" /etc/subuid 2>/dev/null; then
      echo "$USER:100000:65536" | sudo tee -a /etc/subuid
    fi
    if ! grep -q "^$USER:" /etc/subgid 2>/dev/null; then
      echo "$USER:100000:65536" | sudo tee -a /etc/subgid
    fi
  '
  echo ""
}

apply_home_manager() {
  info "Applying home-manager configuration..."

  local remote_home
  remote_home=$(ssh "$TARGET_HOST" "echo \$HOME")

  # Source nix profile and run home-manager
  ssh -A "$TARGET_HOST" "
    # Source nix (for non-NixOS systems)
    if [ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
      . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
    fi

    cd '$remote_home/.config/home-manager'
    export NIX_CONFIG='experimental-features = nix-command flakes'
    nix --max-jobs 1 run home-manager -- switch --impure --flake .#agent-$ARCH -b backup
  "

  success "Configuration applied"
  echo ""
}

# --- Main ---
main() {
  parse_args "$@"
  print_header
  prompt_target_host
  detect_system
  detect_git_identity
  prompt_api_keys
  prompt_git_identity
  install_nix
  setup_swap
  setup_podman
  setup_config
  apply_home_manager

  echo ""
  success "Deployment complete!"
  echo ""
  echo "To clone your repos, connect with: ssh -A $TARGET_HOST"
  echo "Then run sandbox-key to set up a permanent SSH key for this machine."
}

main "$@"
