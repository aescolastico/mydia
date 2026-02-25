{ ... }:

{
  flake.nixosModules.default = import ../module.nix;
  flake.nixosModules.mydia = import ../module.nix;
}
