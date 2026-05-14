{ lib, beamPackages, overrides ? (x: y: {}) }:

let
  buildRebar3 = lib.makeOverridable beamPackages.buildRebar3;
  buildMix = lib.makeOverridable beamPackages.buildMix;
  buildErlangMk = lib.makeOverridable beamPackages.buildErlangMk;

  self = packages // (overrides self packages);

  packages = with beamPackages; with self; {
    absinthe = buildMix rec {
      name = "absinthe";
      version = "1.9.0";

      src = fetchHex {
        pkg = "absinthe";
        version = "${version}";
        sha256 = "db65993420944ad90e932827663d4ab704262b007d4e3900cd69615f14ccc8ce";
      };

      beamDeps = [ dataloader decimal nimble_parsec telemetry ];
    };

    absinthe_phoenix = buildMix rec {
      name = "absinthe_phoenix";
      version = "2.0.4";

      src = fetchHex {
        pkg = "absinthe_phoenix";
        version = "${version}";
        sha256 = "66617ee63b725256ca16264364148b10b19e2ecb177488cd6353584f2e6c1cf3";
      };

      beamDeps = [ absinthe absinthe_plug decimal phoenix phoenix_html phoenix_pubsub ];
    };

    absinthe_plug = buildMix rec {
      name = "absinthe_plug";
      version = "1.5.9";

      src = fetchHex {
        pkg = "absinthe_plug";
        version = "${version}";
        sha256 = "dcdc84334b0e9e2cd439bd2653678a822623f212c71088edf0a4a7d03f1fa225";
      };

      beamDeps = [ absinthe plug ];
    };

    absinthe_relay = buildMix rec {
      name = "absinthe_relay";
      version = "1.6.0";

      src = fetchHex {
        pkg = "absinthe_relay";
        version = "${version}";
        sha256 = "32d6397a7af3fd02678ef9bc8e2f574487f14593cb3e4f9110fb1c695d4d2ac0";
      };

      beamDeps = [ absinthe ecto ];
    };

    argon2_elixir = buildMix rec {
      name = "argon2_elixir";
      version = "4.1.3";

      src = fetchHex {
        pkg = "argon2_elixir";
        version = "${version}";
        sha256 = "7c295b8d8e0eaf6f43641698f962526cdf87c6feb7d14bd21e599271b510608c";
      };

      beamDeps = [ comeonin elixir_make ];
    };

    bandit = buildMix rec {
      name = "bandit";
      version = "1.8.0";

      src = fetchHex {
        pkg = "bandit";
        version = "${version}";
        sha256 = "8458ff4eed20ff2a2ea69d4854883a077c33ea42b51f6811b044ceee0fa15422";
      };

      beamDeps = [ hpax plug telemetry thousand_island websock ];
    };

    bcrypt_elixir = buildMix rec {
      name = "bcrypt_elixir";
      version = "3.3.2";

      src = fetchHex {
        pkg = "bcrypt_elixir";
        version = "${version}";
        sha256 = "471be5151874ae7931911057d1467d908955f93554f7a6cd1b7d804cac8cef53";
      };

      beamDeps = [ comeonin elixir_make ];
    };

    bunt = buildMix rec {
      name = "bunt";
      version = "1.0.0";

      src = fetchHex {
        pkg = "bunt";
        version = "${version}";
        sha256 = "dc5f86aa08a5f6fa6b8096f0735c4e76d54ae5c9fa2c143e5a1fc7c1cd9bb6b5";
      };

      beamDeps = [];
    };

    bypass = buildMix rec {
      name = "bypass";
      version = "2.1.0";

      src = fetchHex {
        pkg = "bypass";
        version = "${version}";
        sha256 = "d9b5df8fa5b7a6efa08384e9bbecfe4ce61c77d28a4282f79e02f1ef78d96b80";
      };

      beamDeps = [ plug plug_cowboy ranch ];
    };

    cc_precompiler = buildMix rec {
      name = "cc_precompiler";
      version = "0.1.11";

      src = fetchHex {
        pkg = "cc_precompiler";
        version = "${version}";
        sha256 = "3427232caf0835f94680e5bcf082408a70b48ad68a5f5c0b02a3bea9f3a075b9";
      };

      beamDeps = [ elixir_make ];
    };

    certifi = buildRebar3 rec {
      name = "certifi";
      version = "2.15.0";

      src = fetchHex {
        pkg = "certifi";
        version = "${version}";
        sha256 = "b147ed22ce71d72eafdad94f055165c1c182f61a2ff49df28bcc71d1d5b94a60";
      };

      beamDeps = [];
    };

    combine = buildMix rec {
      name = "combine";
      version = "0.10.0";

      src = fetchHex {
        pkg = "combine";
        version = "${version}";
        sha256 = "1b1dbc1790073076580d0d1d64e42eae2366583e7aecd455d1215b0d16f2451b";
      };

      beamDeps = [];
    };

    comeonin = buildMix rec {
      name = "comeonin";
      version = "5.5.1";

      src = fetchHex {
        pkg = "comeonin";
        version = "${version}";
        sha256 = "65aac8f19938145377cee73973f192c5645873dcf550a8a6b18187d17c13ccdb";
      };

      beamDeps = [];
    };

    corsica = buildMix rec {
      name = "corsica";
      version = "2.1.3";

      src = fetchHex {
        pkg = "corsica";
        version = "${version}";
        sha256 = "616c08f61a345780c2cf662ff226816f04d8868e12054e68963e95285b5be8bc";
      };

      beamDeps = [ plug telemetry ];
    };

    cowboy = buildErlangMk rec {
      name = "cowboy";
      version = "2.14.2";

      src = fetchHex {
        pkg = "cowboy";
        version = "${version}";
        sha256 = "569081da046e7b41b5df36aa359be71a0c8874e5b9cff6f747073fc57baf1ab9";
      };

      beamDeps = [ cowlib ranch ];
    };

    cowboy_telemetry = buildRebar3 rec {
      name = "cowboy_telemetry";
      version = "0.4.0";

      src = fetchHex {
        pkg = "cowboy_telemetry";
        version = "${version}";
        sha256 = "7d98bac1ee4565d31b62d59f8823dfd8356a169e7fcbb83831b8a5397404c9de";
      };

      beamDeps = [ cowboy telemetry ];
    };

    cowlib = buildRebar3 rec {
      name = "cowlib";
      version = "2.16.0";

      src = fetchHex {
        pkg = "cowlib";
        version = "${version}";
        sha256 = "7f478d80d66b747344f0ea7708c187645cfcc08b11aa424632f78e25bf05db51";
      };

      beamDeps = [];
    };

    credo = buildMix rec {
      name = "credo";
      version = "1.7.13";

      src = fetchHex {
        pkg = "credo";
        version = "${version}";
        sha256 = "47641e6d2bbff1e241e87695b29f617f1a8f912adea34296fb10ecc3d7e9e84f";
      };

      beamDeps = [ bunt file_system jason ];
    };

    crontab = buildMix rec {
      name = "crontab";
      version = "1.2.0";

      src = fetchHex {
        pkg = "crontab";
        version = "${version}";
        sha256 = "ebd7ef4d831e1b20fa4700f0de0284a04cac4347e813337978e25b4cc5cc2207";
      };

      beamDeps = [ ecto ];
    };

    dataloader = buildMix rec {
      name = "dataloader";
      version = "2.0.2";

      src = fetchHex {
        pkg = "dataloader";
        version = "${version}";
        sha256 = "4c6cabc0b55e96e7de74d14bf37f4a5786f0ab69aa06764a1f39dda40079b098";
      };

      beamDeps = [ ecto telemetry ];
    };

    db_connection = buildMix rec {
      name = "db_connection";
      version = "2.8.1";

      src = fetchHex {
        pkg = "db_connection";
        version = "${version}";
        sha256 = "a61a3d489b239d76f326e03b98794fb8e45168396c925ef25feb405ed09da8fd";
      };

      beamDeps = [ telemetry ];
    };

    decimal = buildMix rec {
      name = "decimal";
      version = "2.3.0";

      src = fetchHex {
        pkg = "decimal";
        version = "${version}";
        sha256 = "a4d66355cb29cb47c3cf30e71329e58361cfcb37c34235ef3bf1d7bf3773aeac";
      };

      beamDeps = [];
    };

    dialyxir = buildMix rec {
      name = "dialyxir";
      version = "1.4.7";

      src = fetchHex {
        pkg = "dialyxir";
        version = "${version}";
        sha256 = "b34527202e6eb8cee198efec110996c25c5898f43a4094df157f8d28f27d9efe";
      };

      beamDeps = [ erlex ];
    };

    dns_cluster = buildMix rec {
      name = "dns_cluster";
      version = "0.2.0";

      src = fetchHex {
        pkg = "dns_cluster";
        version = "${version}";
        sha256 = "ba6f1893411c69c01b9e8e8f772062535a4cf70f3f35bcc964a324078d8c8240";
      };

      beamDeps = [];
    };

    ecto = buildMix rec {
      name = "ecto";
      version = "3.13.4";

      src = fetchHex {
        pkg = "ecto";
        version = "${version}";
        sha256 = "5ad7d1505685dfa7aaf86b133d54f5ad6c42df0b4553741a1ff48796736e88b2";
      };

      beamDeps = [ decimal jason telemetry ];
    };

    ecto_sql = buildMix rec {
      name = "ecto_sql";
      version = "3.13.2";

      src = fetchHex {
        pkg = "ecto_sql";
        version = "${version}";
        sha256 = "539274ab0ecf1a0078a6a72ef3465629e4d6018a3028095dc90f60a19c371717";
      };

      beamDeps = [ db_connection ecto postgrex telemetry ];
    };

    ecto_sqlite3 = buildMix rec {
      name = "ecto_sqlite3";
      version = "0.22.0";

      src = fetchHex {
        pkg = "ecto_sqlite3";
        version = "${version}";
        sha256 = "5af9e031bffcc5da0b7bca90c271a7b1e7c04a93fecf7f6cd35bc1b1921a64bd";
      };

      beamDeps = [ decimal ecto ecto_sql exqlite ];
    };

    elixir_make = buildMix rec {
      name = "elixir_make";
      version = "0.9.0";

      src = fetchHex {
        pkg = "elixir_make";
        version = "${version}";
        sha256 = "db23d4fd8b757462ad02f8aa73431a426fe6671c80b200d9710caf3d1dd0ffdb";
      };

      beamDeps = [];
    };

    eqrcode = buildMix rec {
      name = "eqrcode";
      version = "0.2.1";

      src = fetchHex {
        pkg = "eqrcode";
        version = "${version}";
        sha256 = "d5828a222b904c68360e7dc2a40c3ef33a1328b7c074583898040f389f928025";
      };

      beamDeps = [];
    };

    erlex = buildMix rec {
      name = "erlex";
      version = "0.2.8";

      src = fetchHex {
        pkg = "erlex";
        version = "${version}";
        sha256 = "9d66ff9fedf69e49dc3fd12831e12a8a37b76f8651dd21cd45fcf5561a8a7590";
      };

      beamDeps = [];
    };

    error_tracker = buildMix rec {
      name = "error_tracker";
      version = "0.7.0";

      src = fetchHex {
        pkg = "error_tracker";
        version = "${version}";
        sha256 = "47189e3b38d69e3caccc2fd6e3badf0dd2a37ebc8d720c8f6d526489dd758b05";
      };

      beamDeps = [ ecto ecto_sql ecto_sqlite3 jason phoenix_ecto phoenix_live_view plug postgrex ];
    };

    esbuild = buildMix rec {
      name = "esbuild";
      version = "0.10.0";

      src = fetchHex {
        pkg = "esbuild";
        version = "${version}";
        sha256 = "468489cda427b974a7cc9f03ace55368a83e1a7be12fba7e30969af78e5f8c70";
      };

      beamDeps = [ jason ];
    };

    ex_machina = buildMix rec {
      name = "ex_machina";
      version = "2.8.0";

      src = fetchHex {
        pkg = "ex_machina";
        version = "${version}";
        sha256 = "79fe1a9c64c0c1c1fab6c4fa5d871682cb90de5885320c187d117004627a7729";
      };

      beamDeps = [ ecto ecto_sql ];
    };

    expo = buildMix rec {
      name = "expo";
      version = "1.1.1";

      src = fetchHex {
        pkg = "expo";
        version = "${version}";
        sha256 = "5fb308b9cb359ae200b7e23d37c76978673aa1b06e2b3075d814ce12c5811640";
      };

      beamDeps = [];
    };

    exqlite = buildMix rec {
      name = "exqlite";
      version = "0.33.1";

      src = fetchHex {
        pkg = "exqlite";
        version = "${version}";
        sha256 = "b3db0c9ae6e5ee7cf84dd0a1b6dc7566b80912eb7746d45370f5666ed66700f9";
      };

      beamDeps = [ cc_precompiler db_connection elixir_make ];
    };

    file_system = buildMix rec {
      name = "file_system";
      version = "1.1.1";

      src = fetchHex {
        pkg = "file_system";
        version = "${version}";
        sha256 = "7a15ff97dfe526aeefb090a7a9d3d03aa907e100e262a0f8f7746b78f8f87a5d";
      };

      beamDeps = [];
    };

    finch = buildMix rec {
      name = "finch";
      version = "0.20.0";

      src = fetchHex {
        pkg = "finch";
        version = "${version}";
        sha256 = "2658131a74d051aabfcba936093c903b8e89da9a1b63e430bee62045fa9b2ee2";
      };

      beamDeps = [ mime mint nimble_options nimble_pool telemetry ];
    };

    fine = buildMix rec {
      name = "fine";
      version = "0.1.4";

      src = fetchHex {
        pkg = "fine";
        version = "${version}";
        sha256 = "be3324cc454a42d80951cf6023b9954e9ff27c6daa255483b3e8d608670303f5";
      };

      beamDeps = [];
    };

    floki = buildMix rec {
      name = "floki";
      version = "0.38.0";

      src = fetchHex {
        pkg = "floki";
        version = "${version}";
        sha256 = "a5943ee91e93fb2d635b612caf5508e36d37548e84928463ef9dd986f0d1abd9";
      };

      beamDeps = [];
    };

    gettext = buildMix rec {
      name = "gettext";
      version = "0.26.2";

      src = fetchHex {
        pkg = "gettext";
        version = "${version}";
        sha256 = "aa978504bcf76511efdc22d580ba08e2279caab1066b76bb9aa81c4a1e0a32a5";
      };

      beamDeps = [ expo ];
    };

    guardian = buildMix rec {
      name = "guardian";
      version = "2.4.0";

      src = fetchHex {
        pkg = "guardian";
        version = "${version}";
        sha256 = "5c80103a9c538fbc2505bf08421a82e8f815deba9eaedb6e734c66443154c518";
      };

      beamDeps = [ jose plug ];
    };

    hackney = buildRebar3 rec {
      name = "hackney";
      version = "1.25.0";

      src = fetchHex {
        pkg = "hackney";
        version = "${version}";
        sha256 = "7209bfd75fd1f42467211ff8f59ea74d6f2a9e81cbcee95a56711ee79fd6b1d4";
      };

      beamDeps = [ certifi idna metrics mimerl parse_trans ssl_verify_fun unicode_util_compat ];
    };

    hpax = buildMix rec {
      name = "hpax";
      version = "1.0.3";

      src = fetchHex {
        pkg = "hpax";
        version = "${version}";
        sha256 = "8eab6e1cfa8d5918c2ce4ba43588e894af35dbd8e91e6e55c817bca5847df34a";
      };

      beamDeps = [];
    };

    httpoison = buildMix rec {
      name = "httpoison";
      version = "2.3.0";

      src = fetchHex {
        pkg = "httpoison";
        version = "${version}";
        sha256 = "d388ee70be56d31a901e333dbcdab3682d356f651f93cf492ba9f06056436a2c";
      };

      beamDeps = [ hackney ];
    };

    idna = buildRebar3 rec {
      name = "idna";
      version = "6.1.1";

      src = fetchHex {
        pkg = "idna";
        version = "${version}";
        sha256 = "92376eb7894412ed19ac475e4a86f7b413c1b9fbb5bd16dccd57934157944cea";
      };

      beamDeps = [ unicode_util_compat ];
    };

    jason = buildMix rec {
      name = "jason";
      version = "1.4.4";

      src = fetchHex {
        pkg = "jason";
        version = "${version}";
        sha256 = "c5eb0cab91f094599f94d55bc63409236a8ec69a21a67814529e8d5f6cc90b3b";
      };

      beamDeps = [ decimal ];
    };

    jose = buildMix rec {
      name = "jose";
      version = "1.11.10";

      src = fetchHex {
        pkg = "jose";
        version = "${version}";
        sha256 = "0d6cd36ff8ba174db29148fc112b5842186b68a90ce9fc2b3ec3afe76593e614";
      };

      beamDeps = [];
    };

    lazy_html = buildMix rec {
      name = "lazy_html";
      version = "0.1.8";

      src = fetchHex {
        pkg = "lazy_html";
        version = "${version}";
        sha256 = "0d8167d930b704feb94b41414ca7f5779dff9bca7fcf619fcef18de138f08736";
      };

      beamDeps = [ cc_precompiler elixir_make fine ];
    };

    logger_backends = buildMix rec {
      name = "logger_backends";
      version = "1.0.0";

      src = fetchHex {
        pkg = "logger_backends";
        version = "${version}";
        sha256 = "1faceb3e7ec3ef66a8f5746c5afd020e63996df6fd4eb8cdb789e5665ae6c9ce";
      };

      beamDeps = [];
    };

    luerl = buildRebar3 rec {
      name = "luerl";
      version = "1.5.0";

      src = fetchHex {
        pkg = "luerl";
        version = "${version}";
        sha256 = "76612d8b94a93f622f483e90a4d277a007590e12dceb9b35c8ff4be32d644484";
      };

      beamDeps = [];
    };

    metrics = buildRebar3 rec {
      name = "metrics";
      version = "1.0.1";

      src = fetchHex {
        pkg = "metrics";
        version = "${version}";
        sha256 = "69b09adddc4f74a40716ae54d140f93beb0fb8978d8636eaded0c31b6f099f16";
      };

      beamDeps = [];
    };

    mime = buildMix rec {
      name = "mime";
      version = "2.0.7";

      src = fetchHex {
        pkg = "mime";
        version = "${version}";
        sha256 = "6171188e399ee16023ffc5b76ce445eb6d9672e2e241d2df6050f3c771e80ccd";
      };

      beamDeps = [];
    };

    mimerl = buildRebar3 rec {
      name = "mimerl";
      version = "1.4.0";

      src = fetchHex {
        pkg = "mimerl";
        version = "${version}";
        sha256 = "13af15f9f68c65884ecca3a3891d50a7b57d82152792f3e19d88650aa126b144";
      };

      beamDeps = [];
    };

    mint = buildMix rec {
      name = "mint";
      version = "1.7.1";

      src = fetchHex {
        pkg = "mint";
        version = "${version}";
        sha256 = "fceba0a4d0f24301ddee3024ae116df1c3f4bb7a563a731f45fdfeb9d39a231b";
      };

      beamDeps = [ hpax ];
    };

    nimble_options = buildMix rec {
      name = "nimble_options";
      version = "1.1.1";

      src = fetchHex {
        pkg = "nimble_options";
        version = "${version}";
        sha256 = "821b2470ca9442c4b6984882fe9bb0389371b8ddec4d45a9504f00a66f650b44";
      };

      beamDeps = [];
    };

    nimble_parsec = buildMix rec {
      name = "nimble_parsec";
      version = "1.4.2";

      src = fetchHex {
        pkg = "nimble_parsec";
        version = "${version}";
        sha256 = "4b21398942dda052b403bbe1da991ccd03a053668d147d53fb8c4e0efe09c973";
      };

      beamDeps = [];
    };

    nimble_pool = buildMix rec {
      name = "nimble_pool";
      version = "1.1.0";

      src = fetchHex {
        pkg = "nimble_pool";
        version = "${version}";
        sha256 = "af2e4e6b34197db81f7aad230c1118eac993acc0dae6bc83bac0126d4ae0813a";
      };

      beamDeps = [];
    };

    oban = buildMix rec {
      name = "oban";
      version = "2.20.1";

      src = fetchHex {
        pkg = "oban";
        version = "${version}";
        sha256 = "17a45277dbeb41a455040b41dd8c467163fad685d1366f2f59207def3bcdd1d8";
      };

      beamDeps = [ ecto_sql ecto_sqlite3 jason postgrex telemetry ];
    };

    oidcc = buildMix rec {
      name = "oidcc";
      version = "3.6.0";

      src = fetchHex {
        pkg = "oidcc";
        version = "${version}";
        sha256 = "99b26b1db95d617150416b18a7a84bb09525007fdbbcf963a60edb6156c6a1ce";
      };

      beamDeps = [ jose telemetry telemetry_registry ];
    };

    parse_trans = buildRebar3 rec {
      name = "parse_trans";
      version = "3.4.1";

      src = fetchHex {
        pkg = "parse_trans";
        version = "${version}";
        sha256 = "620a406ce75dada827b82e453c19cf06776be266f5a67cff34e1ef2cbb60e49a";
      };

      beamDeps = [];
    };

    phoenix = buildMix rec {
      name = "phoenix";
      version = "1.8.1";

      src = fetchHex {
        pkg = "phoenix";
        version = "${version}";
        sha256 = "84d77d2b2e77c3c7e7527099bd01ef5c8560cd149c036d6b3a40745f11cd2fb2";
      };

      beamDeps = [ bandit jason phoenix_pubsub phoenix_template plug plug_cowboy plug_crypto telemetry websock_adapter ];
    };

    phoenix_ecto = buildMix rec {
      name = "phoenix_ecto";
      version = "4.6.5";

      src = fetchHex {
        pkg = "phoenix_ecto";
        version = "${version}";
        sha256 = "26ec3208eef407f31b748cadd044045c6fd485fbff168e35963d2f9dfff28d4b";
      };

      beamDeps = [ ecto phoenix_html plug postgrex ];
    };

    phoenix_html = buildMix rec {
      name = "phoenix_html";
      version = "4.3.0";

      src = fetchHex {
        pkg = "phoenix_html";
        version = "${version}";
        sha256 = "3eaa290a78bab0f075f791a46a981bbe769d94bc776869f4f3063a14f30497ad";
      };

      beamDeps = [];
    };

    phoenix_live_dashboard = buildMix rec {
      name = "phoenix_live_dashboard";
      version = "0.8.7";

      src = fetchHex {
        pkg = "phoenix_live_dashboard";
        version = "${version}";
        sha256 = "3a8625cab39ec261d48a13b7468dc619c0ede099601b084e343968309bd4d7d7";
      };

      beamDeps = [ ecto mime phoenix_live_view telemetry_metrics ];
    };

    phoenix_live_reload = buildMix rec {
      name = "phoenix_live_reload";
      version = "1.6.1";

      src = fetchHex {
        pkg = "phoenix_live_reload";
        version = "${version}";
        sha256 = "74273843d5a6e4fef0bbc17599f33e3ec63f08e69215623a0cd91eea4288e5a0";
      };

      beamDeps = [ file_system phoenix ];
    };

    phoenix_live_view = buildMix rec {
      name = "phoenix_live_view";
      version = "1.1.16";

      src = fetchHex {
        pkg = "phoenix_live_view";
        version = "${version}";
        sha256 = "f2a0093895b8ef4880af76d41de4a9cf7cff6c66ad130e15a70bdabc4d279feb";
      };

      beamDeps = [ jason lazy_html phoenix phoenix_html phoenix_template plug telemetry ];
    };

    phoenix_pubsub = buildMix rec {
      name = "phoenix_pubsub";
      version = "2.2.0";

      src = fetchHex {
        pkg = "phoenix_pubsub";
        version = "${version}";
        sha256 = "adc313a5bf7136039f63cfd9668fde73bba0765e0614cba80c06ac9460ff3e96";
      };

      beamDeps = [];
    };

    phoenix_template = buildMix rec {
      name = "phoenix_template";
      version = "1.0.4";

      src = fetchHex {
        pkg = "phoenix_template";
        version = "${version}";
        sha256 = "2c0c81f0e5c6753faf5cca2f229c9709919aba34fab866d3bc05060c9c444206";
      };

      beamDeps = [ phoenix_html ];
    };

    plug = buildMix rec {
      name = "plug";
      version = "1.18.1";

      src = fetchHex {
        pkg = "plug";
        version = "${version}";
        sha256 = "57a57db70df2b422b564437d2d33cf8d33cd16339c1edb190cd11b1a3a546cc2";
      };

      beamDeps = [ mime plug_crypto telemetry ];
    };

    plug_cowboy = buildMix rec {
      name = "plug_cowboy";
      version = "2.7.4";

      src = fetchHex {
        pkg = "plug_cowboy";
        version = "${version}";
        sha256 = "9b85632bd7012615bae0a5d70084deb1b25d2bcbb32cab82d1e9a1e023168aa3";
      };

      beamDeps = [ cowboy cowboy_telemetry plug ];
    };

    plug_crypto = buildMix rec {
      name = "plug_crypto";
      version = "2.1.1";

      src = fetchHex {
        pkg = "plug_crypto";
        version = "${version}";
        sha256 = "6470bce6ffe41c8bd497612ffde1a7e4af67f36a15eea5f921af71cf3e11247c";
      };

      beamDeps = [];
    };

    postgrex = buildMix rec {
      name = "postgrex";
      version = "0.21.1";

      src = fetchHex {
        pkg = "postgrex";
        version = "${version}";
        sha256 = "27d8d21c103c3cc68851b533ff99eef353e6a0ff98dc444ea751de43eb48bdac";
      };

      beamDeps = [ db_connection decimal jason ];
    };

    ranch = buildRebar3 rec {
      name = "ranch";
      version = "1.8.1";

      src = fetchHex {
        pkg = "ranch";
        version = "${version}";
        sha256 = "aed58910f4e21deea992a67bf51632b6d60114895eb03bb392bb733064594dd0";
      };

      beamDeps = [];
    };

    req = buildMix rec {
      name = "req";
      version = "0.5.15";

      src = fetchHex {
        pkg = "req";
        version = "${version}";
        sha256 = "a6513a35fad65467893ced9785457e91693352c70b58bbc045b47e5eb2ef0c53";
      };

      beamDeps = [ finch jason mime plug ];
    };

    rustler = buildMix rec {
      name = "rustler";
      version = "0.34.0";

      src = fetchHex {
        pkg = "rustler";
        version = "${version}";
        sha256 = "1d0c7449482b459513003230c0e2422b0252245776fe6fd6e41cb2b11bd8e628";
      };

      beamDeps = [ jason req toml ];
    };

    ssl_verify_fun = buildRebar3 rec {
      name = "ssl_verify_fun";
      version = "1.1.7";

      src = fetchHex {
        pkg = "ssl_verify_fun";
        version = "${version}";
        sha256 = "fe4c190e8f37401d30167c8c405eda19469f34577987c76dde613e838bbc67f8";
      };

      beamDeps = [];
    };

    sweet_xml = buildMix rec {
      name = "sweet_xml";
      version = "0.7.5";

      src = fetchHex {
        pkg = "sweet_xml";
        version = "${version}";
        sha256 = "193b28a9b12891cae351d81a0cead165ffe67df1b73fe5866d10629f4faefb12";
      };

      beamDeps = [];
    };

    tailwind = buildMix rec {
      name = "tailwind";
      version = "0.4.1";

      src = fetchHex {
        pkg = "tailwind";
        version = "${version}";
        sha256 = "6249d4f9819052911120dbdbe9e532e6bd64ea23476056adb7f730aa25c220d1";
      };

      beamDeps = [];
    };

    telemetry = buildRebar3 rec {
      name = "telemetry";
      version = "1.3.0";

      src = fetchHex {
        pkg = "telemetry";
        version = "${version}";
        sha256 = "7015fc8919dbe63764f4b4b87a95b7c0996bd539e0d499be6ec9d7f3875b79e6";
      };

      beamDeps = [];
    };

    telemetry_metrics = buildMix rec {
      name = "telemetry_metrics";
      version = "1.1.0";

      src = fetchHex {
        pkg = "telemetry_metrics";
        version = "${version}";
        sha256 = "e7b79e8ddfde70adb6db8a6623d1778ec66401f366e9a8f5dd0955c56bc8ce67";
      };

      beamDeps = [ telemetry ];
    };

    telemetry_poller = buildRebar3 rec {
      name = "telemetry_poller";
      version = "1.3.0";

      src = fetchHex {
        pkg = "telemetry_poller";
        version = "${version}";
        sha256 = "51f18bed7128544a50f75897db9974436ea9bfba560420b646af27a9a9b35211";
      };

      beamDeps = [ telemetry ];
    };

    telemetry_registry = buildMix rec {
      name = "telemetry_registry";
      version = "0.3.2";

      src = fetchHex {
        pkg = "telemetry_registry";
        version = "${version}";
        sha256 = "e7ed191eb1d115a3034af8e1e35e4e63d5348851d556646d46ca3d1b4e16bab9";
      };

      beamDeps = [ telemetry ];
    };

    tesla = buildMix rec {
      name = "tesla";
      version = "1.15.3";

      src = fetchHex {
        pkg = "tesla";
        version = "${version}";
        sha256 = "98bb3d4558abc67b92fb7be4cd31bb57ca8d80792de26870d362974b58caeda7";
      };

      beamDeps = [ finch hackney jason mime mint telemetry ];
    };

    thousand_island = buildMix rec {
      name = "thousand_island";
      version = "1.4.2";

      src = fetchHex {
        pkg = "thousand_island";
        version = "${version}";
        sha256 = "1c7637f16558fc1c35746d5ee0e83b18b8e59e18d28affd1f2fa1645f8bc7473";
      };

      beamDeps = [ telemetry ];
    };

    timex = buildMix rec {
      name = "timex";
      version = "3.7.13";

      src = fetchHex {
        pkg = "timex";
        version = "${version}";
        sha256 = "09588e0522669328e973b8b4fd8741246321b3f0d32735b589f78b136e6d4c54";
      };

      beamDeps = [ combine gettext tzdata ];
    };

    toml = buildMix rec {
      name = "toml";
      version = "0.7.0";

      src = fetchHex {
        pkg = "toml";
        version = "${version}";
        sha256 = "0690246a2478c1defd100b0c9b89b4ea280a22be9a7b313a8a058a2408a2fa70";
      };

      beamDeps = [];
    };

    tzdata = buildMix rec {
      name = "tzdata";
      version = "1.1.3";

      src = fetchHex {
        pkg = "tzdata";
        version = "${version}";
        sha256 = "d4ca85575a064d29d4e94253ee95912edfb165938743dbf002acdf0dcecb0c28";
      };

      beamDeps = [ hackney ];
    };

    ueberauth = buildMix rec {
      name = "ueberauth";
      version = "0.10.8";

      src = fetchHex {
        pkg = "ueberauth";
        version = "${version}";
        sha256 = "f2d3172e52821375bccb8460e5fa5cb91cfd60b19b636b6e57e9759b6f8c10c1";
      };

      beamDeps = [ plug ];
    };

    ueberauth_oidcc = buildMix rec {
      name = "ueberauth_oidcc";
      version = "0.4.2";

      src = fetchHex {
        pkg = "ueberauth_oidcc";
        version = "${version}";
        sha256 = "b9ea3c981464a5052e4f4fbf0a3c716e124da056aca30b9754654c5c6f90f8c2";
      };

      beamDeps = [ oidcc plug ueberauth ];
    };

    unicode_util_compat = buildRebar3 rec {
      name = "unicode_util_compat";
      version = "0.7.1";

      src = fetchHex {
        pkg = "unicode_util_compat";
        version = "${version}";
        sha256 = "b3a917854ce3ae233619744ad1e0102e05673136776fb2fa76234f3e03b23642";
      };

      beamDeps = [];
    };

    wallaby = buildMix rec {
      name = "wallaby";
      version = "0.30.11";

      src = fetchHex {
        pkg = "wallaby";
        version = "${version}";
        sha256 = "407b50972e3827ce77e3b8292c36dcbd6b21b6837cc4f12ee8767e92a72610ac";
      };

      beamDeps = [ ecto_sql httpoison jason phoenix_ecto web_driver_client ];
    };

    web_driver_client = buildMix rec {
      name = "web_driver_client";
      version = "0.2.0";

      src = fetchHex {
        pkg = "web_driver_client";
        version = "${version}";
        sha256 = "83cc6092bc3e74926d1c8455f0ce927d5d1d36707b74d9a65e38c084aab0350f";
      };

      beamDeps = [ hackney jason tesla ];
    };

    websock = buildMix rec {
      name = "websock";
      version = "0.5.3";

      src = fetchHex {
        pkg = "websock";
        version = "${version}";
        sha256 = "6105453d7fac22c712ad66fab1d45abdf049868f253cf719b625151460b8b453";
      };

      beamDeps = [];
    };

    websock_adapter = buildMix rec {
      name = "websock_adapter";
      version = "0.5.8";

      src = fetchHex {
        pkg = "websock_adapter";
        version = "${version}";
        sha256 = "315b9a1865552212b5f35140ad194e67ce31af45bcee443d4ecb96b5fd3f3782";
      };

      beamDeps = [ bandit plug plug_cowboy websock ];
    };

    websockex = buildMix rec {
      name = "websockex";
      version = "0.4.3";

      src = fetchHex {
        pkg = "websockex";
        version = "${version}";
        sha256 = "95f2e7072b85a3a4cc385602d42115b73ce0b74a9121d0d6dbbf557645ac53e4";
      };

      beamDeps = [];
    };

    yamerl = buildRebar3 rec {
      name = "yamerl";
      version = "0.10.0";

      src = fetchHex {
        pkg = "yamerl";
        version = "${version}";
        sha256 = "346adb2963f1051dc837a2364e4acf6eb7d80097c0f53cbdc3046ec8ec4b4e6e";
      };

      beamDeps = [];
    };

    yaml_elixir = buildMix rec {
      name = "yaml_elixir";
      version = "2.12.0";

      src = fetchHex {
        pkg = "yaml_elixir";
        version = "${version}";
        sha256 = "ca6bacae7bac917a7155dca0ab6149088aa7bc800c94d0fe18c5238f53b313c6";
      };

      beamDeps = [ yamerl ];
    };

    ymlr = buildMix rec {
      name = "ymlr";
      version = "5.1.4";

      src = fetchHex {
        pkg = "ymlr";
        version = "${version}";
        sha256 = "75f16cf0709fbd911b30311a0359a7aa4b5476346c01882addefd5f2b1cfaa51";
      };

      beamDeps = [];
    };
  };
in self

