{
  pkgs,
  nixpkgs,
  configName,
  minecraftVersion,
  gameConfig,
  versionData,
  fabricLoaderData,
  isFabric,
  jvmArgsString,
  sources,
  resolvedMods,
  javaRuntime,
}:
pkgs.writeShellApplication {
  name = "minecraft";

  runtimeInputs = [
    javaRuntime
    (pkgs.python3.withPackages
      (ps: [
        ps.aiohttp
      ]))
  ];

  text = ''
    GAME_DIR="''${GAME_DIR:-$HOME/.minecraft-nix-instances/${configName}}"
    MODS_DIR="$GAME_DIR/mods"
    LOGS_DIR="$GAME_DIR/logs"
    mkdir -p "$GAME_DIR" "$MODS_DIR" "$LOGS_DIR" "$GAME_DIR/assets" "$GAME_DIR/assets/indexes" "$GAME_DIR/assets/objects"
    cd "$GAME_DIR"

    rm -f "$MODS_DIR"/*.jar
    ${nixpkgs.lib.concatMapStringsSep "\n" (modPath: ''
        ln -sf "${modPath}" "$MODS_DIR/${builtins.baseNameOf modPath}"
      '')
      resolvedMods}

    ASSET_ID="${versionData.assetIndex.id}"
    INDEX_LINK_PATH="$GAME_DIR/assets/indexes/$ASSET_ID.json"
    if [ -L "$INDEX_LINK_PATH" ] || [ -e "$INDEX_LINK_PATH" ]; then
      rm -f "$INDEX_LINK_PATH"
    fi
    ln -s "${sources.assetIndex}" "$INDEX_LINK_PATH"

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
      ${sources.loggingArgs} \
      -Dlog_dir="$LOGS_DIR" \
      -cp "${sources.clientClasspath}" \
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
}
