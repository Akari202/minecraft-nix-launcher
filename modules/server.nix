{
  pkgs,
  nixpkgs,
  configName,
  minecraftVersion,
  gameConfig,
  fabricLoaderData,
  isFabric,
  sources,
  serverPropertiesFile,
  serverLists,
  serverIcon,
  resolvedMods,
  javaRuntime,
}:
pkgs.writeShellApplication {
  name = "minecraft-server";
  runtimeInputs = [javaRuntime];
  text = ''
    SERVER_DIR="''${SERVER_DIR:-$HOME/.minecraft-nix-servers/${configName}}"
    MODS_DIR="$SERVER_DIR/mods"
    mkdir -p "$SERVER_DIR" "$MODS_DIR"
    cd "$SERVER_DIR"

    rm -f "$MODS_DIR"/*.jar
    ${nixpkgs.lib.concatMapStringsSep "\n" (modPath: ''
        ln -sf "${modPath}" "$MODS_DIR/${builtins.baseNameOf modPath}"
      '')
      resolvedMods}

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
      -cp "${sources.serverClasspath}" \
      ${
      if isFabric
      then fabricLoaderData.serverMainClass
      else "net.minecraft.server.Main"
    } \
      nogui \
      "$@"
  '';
}
