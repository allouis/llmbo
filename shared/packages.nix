# Shared package list for both home-manager and NixOS modes
{ pkgs, llmPkgs, useDocker ? false }:

with pkgs; [
  # LLM agents
  llmPkgs.claude-code
  llmPkgs.opencode
  llmPkgs.happy-coder
  llmPkgs.beads
  llmPkgs.openspec
  llmPkgs.agent-browser

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
  tmux
  gettext  # provides envsubst
  ntfy-sh

  # Node.js
  nodejs_22  # LTS
  (yarn.override { nodejs = nodejs_22; })

  # Build tools (for native modules like re2)
  gnumake
  gcc
  pkg-config
  # Python with setuptools for node-gyp (distutils was removed in Python 3.12+)
  (python3.withPackages (ps: [ ps.setuptools ]))
] ++ (if useDocker then [
  # Wrapper so `docker-compose` delegates to `docker compose` (the CLI plugin),
  # which properly discovers buildx and other plugins
  (writeShellScriptBin "docker-compose" ''exec docker compose "$@"'')
] else [
  # Containers (podman as rootless docker replacement)
  podman
  podman-compose
  # CLI wrappers (aliases don't work in scripts/subshells)
  (writeShellScriptBin "docker" ''exec podman "$@"'')
  (writeShellScriptBin "docker-compose" ''exec podman-compose "$@"'')
])
