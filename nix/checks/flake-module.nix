{ ... }:

{
  perSystem = { pkgs, self', ... }: {
    checks = {
      # Verify both package variants build successfully
      package = self'.packages.default;
      package-postgres = self'.packages.postgres;
    } // pkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
      # NixOS module VM tests (Linux only — requires QEMU)
      nixos-module = import ../tests/module.nix {
        inherit pkgs;
        mydiaPackage = self'.packages.default;
      };
      nixos-module-postgres = import ../tests/module-postgres.nix {
        inherit pkgs;
        mydiaPackage = self'.packages.postgres;
      };
    };
  };
}
