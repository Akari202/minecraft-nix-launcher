{
  nixpkgs,
  system,
  minecraftVersion,
  configName,
  gameConfig,
}: let
  pkgs = nixpkgs.legacyPackages.${system};
  versions = import ../pkgs/versions.nix;
  versionData = versions.versions.${minecraftVersion};

  fabricVersions = import ../pkgs/fabric-versions.nix;
  isFabric = gameConfig ? fabricLoaderVersion && gameConfig.fabricLoaderVersion != null;
  fabricLoaderData =
    if isFabric
    then fabricVersions.${gameConfig.fabricLoaderVersion}
    else null;

  serverPropertiesFile = import ./server-properties.nix {
    inherit pkgs nixpkgs;
    userProperties = gameConfig.serverProperties or {};
  };

  serverLists = import ./server-lists.nix {
    inherit pkgs;
    userLists = gameConfig.serverLists or {};
  };

  serverIcon =
    if (gameConfig ? serverIconUrl && gameConfig ? serverIconSha256)
    then
      pkgs.fetchurl {
        url = gameConfig.serverIconUrl;
        sha256 = gameConfig.serverIconSha256;
      }
    else null;

  jvmArgsString = import ./jvm-args.nix {
    inherit system nixpkgs;
    jvmArgs = versionData.jvmArgs;
  };

  javaRuntime = pkgs."jdk${toString versionData.javaVersion}";

  fetchSource = lib:
    pkgs.fetchurl {
      url = lib.url;
      sha256 = lib.sha256;
      name = builtins.baseNameOf lib.url;
    };

  assetIndex = fetchSource versionData.assetIndex;

  sharedLibraries =
    (map fetchSource versionData.libraries)
    ++ (
      if isFabric
      then
        (map fetchSource fabricLoaderData.commonLibraries)
        ++ [(fetchSource fabricLoaderData.loader)]
      else []
    );

  clientLibraries =
    sharedLibraries
    ++ [(fetchSource versionData.client)]
    ++ (
      if isFabric
      then map fetchSource fabricLoaderData.clientLibraries
      else []
    );

  serverLibraries =
    sharedLibraries
    ++ [(fetchSource versionData.server)]
    ++ (
      if isFabric
      then map fetchSource fabricLoaderData.serverLibraries
      else []
    );

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

  clientClasspath = nixpkgs.lib.strings.concatStringsSep ":" clientLibraries;
  serverClasspath = nixpkgs.lib.strings.concatStringsSep ":" serverLibraries;

  pythonEnv = pkgs.python3.withPackages (ps: [
    ps.aiohttp
  ]);
in {
  default = pkgs.writeShellApplication {
    name = "minecraft";

    runtimeInputs = [
      javaRuntime
      pythonEnv
    ];

    text = ''
      GAME_DIR="''${GAME_DIR:-$HOME/.minecraft-nix-instances/${configName}}"
      MODS_DIR="$GAME_DIR/mods"
      LOGS_DIR="$GAME_DIR/logs"
      mkdir -p "$GAME_DIR" "$MODS_DIR" "$LOGS_DIR" "$GAME_DIR/assets" "$GAME_DIR/assets/indexes" "$GAME_DIR/assets/objects"

      ASSET_ID="${versionData.assetIndex.id}"
      INDEX_LINK_PATH="$GAME_DIR/assets/indexes/$ASSET_ID.json"
      if [ -L "$INDEX_LINK_PATH" ] || [ -e "$INDEX_LINK_PATH" ]; then
        rm -f "$INDEX_LINK_PATH"
      fi
      ln -s "${assetIndex}" "$INDEX_LINK_PATH"

      python3 "${../scripts/asset_downloader.py}" \
        --index "$INDEX_LINK_PATH" \
        --objects-dir "$GAME_DIR/assets/objects"

      echo "Username: ${gameConfig.launchConfig.username}"
      echo "Instance: ${configName}"
      echo "Launching Minecraft: ${minecraftVersion}"
      ${
        if isFabric
        then "echo \"Fabric Loader: ${gameConfig.fabricLoaderVersion}\""
        else ""
      }
      echo "Game Directory: $GAME_DIR"
      echo "Java Version: ${javaRuntime.version}"
      echo "Memory: ${gameConfig.launchConfig.ramMin} - ${gameConfig.launchConfig.ramMax}"
      echo ""

      exec java \
        -Xms${gameConfig.launchConfig.ramMin} \
        -Xmx${gameConfig.launchConfig.ramMax} \
        ${gameConfig.launchConfig.javaArgs} \
        ${jvmArgsString} \
        ${loggingArgs} \
        -Dlog_dir="$LOGS_DIR" \
        -cp "${clientClasspath}" \
        ${
        if isFabric
        then fabricLoaderData.clientMainClass
        else versionData.clientMainClass
      } \
        --gameDir "$GAME_DIR" \
        --username "${gameConfig.launchConfig.username}" \
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
      ${
        if isFabric
        then "echo \"Fabric Loader: ${gameConfig.fabricLoaderVersion}\""
        else ""
      }
      echo "Server Directory: $SERVER_DIR"
      echo "Java Version: ${javaRuntime.version}"
      echo "Memory: ${gameConfig.launchConfig.ramMin} - ${gameConfig.launchConfig.ramMax}"
      echo ""

      exec java \
        -Xms${gameConfig.launchConfig.ramMin} \
        -Xmx${gameConfig.launchConfig.ramMax} \
        ${gameConfig.launchConfig.javaArgs} \
        -cp "${serverClasspath}" \
        ${
        if isFabric
        then fabricLoaderData.serverMainClass
        else "net.minecraft.server.Main"
      } \
        nogui \
        "$@"
    '';
  };

  generate-versions = import ./generate-versions.nix pkgs;
}
