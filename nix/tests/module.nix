{ pkgs, mydiaPackage }:

pkgs.testers.nixosTest {
  name = "mydia-module";

  nodes.machine = { config, pkgs, ... }: {
    imports = [ ../../nix/module.nix ];

    services.mydia = {
      enable = true;
      package = mydiaPackage;
      host = "localhost";
      listenAddress = "0.0.0.0";
      secretKeyBaseFile = pkgs.writeText "test-secret-key-base"
        "test-secret-key-base-that-is-at-least-64-bytes-long-for-phoenix-to-accept-it-ok";
    };

    # Allocate enough memory for the BEAM VM
    virtualisation.memorySize = 1024;
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("mydia.service")
    machine.wait_for_open_port(4000)

    # Verify HTTP endpoint responds
    result = machine.succeed("curl -sf -o /dev/null -w '%{http_code}' http://localhost:4000/")
    assert result.strip("'") in ["200", "302"], f"Expected HTTP 200 or 302, got {result}"

    # Verify user and group were created
    machine.succeed("getent passwd mydia")
    machine.succeed("getent group mydia")

    # Verify data directory exists and is owned by mydia
    machine.succeed("test -d /var/lib/mydia")
    machine.succeed("stat -c '%U:%G' /var/lib/mydia | grep -q 'mydia:mydia'")

    # Verify SQLite database was created (migrations ran)
    machine.succeed("test -f /var/lib/mydia/mydia.db")

    # Verify service stops gracefully (systemctl stop is synchronous)
    machine.succeed("systemctl stop mydia.service")
  '';
}
