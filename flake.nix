{
  description = "Mydia - Self-hosted media management application";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];

      # NOTE: dev shells are no longer provided by this flake. The developer
      # environment lives in devenv.nix (devenv.sh) with per-worktree isolation.
      # The production image, NixOS module, packages, and checks remain here.
      imports = [
        ./nix/packages/flake-module.nix
        ./nix/checks/flake-module.nix
        ./nix/modules/flake-module.nix
      ];
    };
}
