# Shared package list for both home-manager and NixOS modes
{ pkgs, llmPkgs, useDocker ? false }:

with pkgs; [
  # LLM agents
  llmPkgs.claude-code
  llmPkgs.opencode
  llmPkgs.happy-coder

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
  docker-compose
] else [
  # Containers (podman as rootless docker replacement)
  podman
  podman-compose
  # CLI wrappers (aliases don't work in scripts/subshells)
  (writeShellScriptBin "docker" ''exec podman "$@"'')
  (writeShellScriptBin "docker-compose" ''exec podman-compose "$@"'')
])
