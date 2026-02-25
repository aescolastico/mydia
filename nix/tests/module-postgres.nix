{ pkgs, mydiaPackage }:

pkgs.testers.nixosTest {
  name = "mydia-module-postgres";

  nodes.machine = { config, pkgs, ... }: {
    imports = [ ../../nix/module.nix ];

    services.mydia = {
      enable = true;
      package = mydiaPackage;
      host = "localhost";
      listenAddress = "0.0.0.0";
      secretKeyBaseFile = pkgs.writeText "test-secret-key-base"
        "test-secret-key-base-that-is-at-least-64-bytes-long-for-phoenix-to-accept-it-ok";
      database = {
        type = "postgres";
        createLocally = true;
      };
    };

    # Allocate enough memory for PostgreSQL + BEAM VM
    virtualisation.memorySize = 1536;
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("postgresql.service")
    machine.wait_for_unit("mydia.service")
    machine.wait_for_open_port(4000)

    # Verify HTTP endpoint responds
    result = machine.succeed("curl -sf -o /dev/null -w '%{http_code}' http://localhost:4000/")
    assert result.strip("'") in ["200", "302"], f"Expected HTTP 200 or 302, got {result}"

    # Verify user and group were created
    machine.succeed("getent passwd mydia")
    machine.succeed("getent group mydia")

    # Verify data directory exists
    machine.succeed("test -d /var/lib/mydia")

    # Verify PostgreSQL database has tables (migrations ran)
    machine.succeed("sudo -u postgres psql -d mydia -c '\\dt' | grep -q 'users'")

    # Verify NO SQLite database was created
    machine.fail("test -f /var/lib/mydia/mydia.db")

    # Verify service stops gracefully
    machine.succeed("systemctl stop mydia.service")
  '';
}
