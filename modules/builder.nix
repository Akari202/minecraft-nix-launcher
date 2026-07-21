{
  nixpkgs,
  system,
  minecraftVersion,
  configName,
  launchConfig,
}: let
  pkgs = nixpkgs.legacyPackages.${system};
  versions = import ../pkgs/versions.nix;
  versionData = versions.versions.${minecraftVersion};

  assetIndex = pkgs.fetchurl {
    url = versionData.assetIndex.url;
    sha256 = versionData.assetIndex.sha256;
  };

  serverPropertiesFile = import ./server-properties.nix {
    inherit pkgs nixpkgs;
    userProperties = launchConfig.serverProperties or {};
  };

  serverLists = import ./server-lists.nix {
    inherit pkgs;
    userLists = launchConfig.serverLists or {};
  };

  serverIcon =
    if (launchConfig ? serverIconUrl && launchConfig ? serverIconSha256)
    then
      pkgs.fetchurl {
        url = launchConfig.serverIconUrl;
        sha256 = launchConfig.serverIconSha256;
      }
    else null;

  jvmArgsString = import ./jvm-args.nix {
    inherit system nixpkgs;
    jvmArgs = versionData.jvmArgs;
  };

  javaRuntime = pkgs."jdk${toString versionData.javaVersion}";

  vanillaClient = pkgs.fetchurl {
    url = versionData.client.url;
    sha256 = versionData.client.sha256;
  };

  vanillaServer = pkgs.fetchurl {
    url = versionData.server.url;
    sha256 = versionData.server.sha256;
  };

  vanillaLibraries =
    map (
      lib:
        pkgs.fetchurl {
          url = lib.url;
          sha256 = lib.sha256;
          name = builtins.baseNameOf lib.url;
        }
    )
    versionData.libraries;

  allLibraries =
    vanillaLibraries
    ++ [
      vanillaClient
    ];

  rawLoggingConfig = pkgs.fetchurl {
    url = versionData.logging.config.url;
    sha256 = versionData.logging.config.sha256;
  };
  loggingConfig = pkgs.runCommand "client-logging.xml" {} ''
    sed -e 's|fileName="logs/|fileName="\$\{sys:log_dir\}/|g' \
      -e 's|filePattern="logs/|filePattern="\$\{sys:log_dir\}/|g' \
      ${rawLoggingConfig} > $out
  '';
  loggingArgs = nixpkgs.lib.strings.replaceStrings ["\${path}"] ["${loggingConfig}"] versionData.logging.args;

  classpath = nixpkgs.lib.strings.concatStringsSep ":" allLibraries;

  pythonEnv = pkgs.python3.withPackages (ps: [
    ps.aiohttp
  ]);
in {
  default = pkgs.writeShellApplication {
    name = "minecraft";

    runtimeInputs = [
      javaRuntime
      pkgs.python3
      (pkgs.python3.withPackages (ps: [
        ps.aiohttp
      ]))
    ];

    text = ''
      GAME_DIR="''${GAME_DIR:-$HOME/.minecraft-nix-instances/${configName}}"
      mkdir -p "$GAME_DIR"
      MODS_DIR="$GAME_DIR/mods"
      mkdir -p "$MODS_DIR"
      LOGS_DIR="$GAME_DIR/logs"
      mkdir -p "$LOGS_DIR"
      mkdir -p "$GAME_DIR/assets"
      mkdir -p "$GAME_DIR/assets/indexes"
      mkdir -p "$GAME_DIR/assets/objects"


      ASSET_ID="${versionData.assetIndex.id}"
      INDEX_LINK_PATH="$GAME_DIR/assets/indexes/$ASSET_ID.json"
      if [ -L "$INDEX_LINK_PATH" ] || [ -e "$INDEX_LINK_PATH" ]; then
        rm -f "$INDEX_LINK_PATH"
      fi
      ln -s "${assetIndex}" "$INDEX_LINK_PATH"

      ${pythonEnv}/bin/python3 "${../scripts/asset_downloader.py}" \
        --index "$INDEX_LINK_PATH" \
        --objects-dir "$GAME_DIR/assets/objects"

      echo "Username: ${launchConfig.username}"
      echo "Instance: ${configName}"
      echo "Launching Minecraft: ${minecraftVersion}"
      echo "Game Directory: $GAME_DIR"
      echo "Java Version: ${javaRuntime.version}"
      echo "Memory: ${launchConfig.ramMin} - ${launchConfig.ramMax}"
      echo ""

      exec ${javaRuntime}/bin/java \
        -Xms${launchConfig.ramMin} \
        -Xmx${launchConfig.ramMax} \
        ${launchConfig.javaArgs} \
        ${jvmArgsString} \
        ${loggingArgs} \
        -Dlog_dir="$LOGS_DIR" \
        -cp "${classpath}" \
        ${versionData.clientMainClass} \
        --gameDir "$GAME_DIR" \
        --username "${launchConfig.username}" \
        --version "${versionData.version}" \
        --versionType "release" \
        --assetsDir "$GAME_DIR/assets" \
        --assetIndex "$ASSET_ID" \
        --uuid "00000000-0000-0000-0000-000000000000" \
        --accessToken "0" \
        "$@"
    '';
  };

  minecraft-server = pkgs.writeShellApplication {
    name = "minecraft-server";
    runtimeInputs = [javaRuntime];
    text = ''
      SERVER_DIR="''${SERVER_DIR:-$HOME/.minecraft-nix-servers/${configName}}"
      mkdir -p "$SERVER_DIR"
      cd "$SERVER_DIR"

      cp -f "${serverPropertiesFile}" server.properties
      cp -f "${serverLists.opsFile}" ops.json
      cp -f "${serverLists.whitelistFile}" whitelist.json
      cp -f "${serverLists.bannedPlayersFile}" banned-players.json
      cp -f "${serverLists.bannedIpsFile}" banned-ips.json
      chmod 644 ops.json whitelist.json banned-players.json banned-ips.json server.properties
      ${
        if serverIcon != null
        then ''
          cp -f "${serverIcon}" server-icon.png
          chmod 644 server-icon.png
        ''
        else ""
      }

      if [ ! -f eula.txt ]; then
        echo "eula=true" > eula.txt
        echo "Accepted Mojang EULA in eula.txt"
      fi

      echo "Instance: ${configName}"
      echo "Launching Minecraft server: ${minecraftVersion}"
      echo "Server Directory: $SERVER_DIR"
      echo "Java Version: ${javaRuntime.version}"
      echo "Memory: ${launchConfig.ramMin} - ${launchConfig.ramMax}"
      echo ""

      exec ${javaRuntime}/bin/java \
        -Xms${launchConfig.ramMin} \
        -Xmx${launchConfig.ramMax} \
        ${launchConfig.javaArgs} \
        -jar "${vanillaServer}" \
        nogui \
        "$@"
    '';
  };

  generate-versions = import ../scripts/generate-versions.nix pkgs;
}
