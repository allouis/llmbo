# Full NixOS configuration for nixos-anywhere deployment
# System-level config only; user configs handled by home-manager
{ config, pkgs, lib, modulesPath, llmPkgs, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  system.stateVersion = "24.11";

  boot.loader.grub = {
    efiSupport = true;
    efiInstallAsRemovable = true;
  };
  boot.kernelParams = [ "console=ttyS0" ];

  networking.hostName = "agent-machine";
  networking.useDHCP = lib.mkDefault true;
  networking.firewall.enable = true;

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
    # Binary cache
    extra-substituters = [ "https://cache.numtide.com" ];
    extra-trusted-public-keys = [ "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=" ];
  };

  # Real Docker (not podman)
  virtualisation.docker.enable = true;

  # Swap for memory-constrained VMs
  swapDevices = [{
    device = "/swapfile";
    size = 4096;  # 4GB
  }];

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFJmICnIur0KyC/BZybYsiPc1oZq5ZC+UTPqNcxdyHFX"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK5YFCqFE5U1+tC4zio+E54PrjM3jL5FaxCMHFSxQd/l pixel-9a"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOSfUoKIt7TsBSBRnUQL9HrwhHfoFznSuQtEtJ4GE/Is"
  ];

  # Agent user - can SSH in and run LLM agents without root
  users.users.agent = {
    isNormalUser = true;
    extraGroups = [ "docker" "wheel" ];
    home = "/home/agent";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFJmICnIur0KyC/BZybYsiPc1oZq5ZC+UTPqNcxdyHFX"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK5YFCqFE5U1+tC4zio+E54PrjM3jL5FaxCMHFSxQd/l pixel-9a"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOSfUoKIt7TsBSBRnUQL9HrwhHfoFznSuQtEtJ4GE/Is"
    ];
  };

  # Passwordless sudo for agent (sandbox environment)
  security.sudo.extraRules = [{
    users = [ "agent" ];
    commands = [{ command = "ALL"; options = [ "NOPASSWD" ]; }];
  }];

  # Marker file to indicate this NixOS was installed by llmbo
  # Used by deploy.sh to detect re-runs and skip reinstallation
  environment.etc."llmbo".text = "llmbo";

  time.timeZone = "UTC";
}
