{
  nixpkgs,
  system,
  selectedVersion,
  configName,
  launchConfig,
}: let
  pkgs = nixpkgs.legacyPackages.${system};
  versions = import ./versions.nix;
  versionData = versions.versions.${selectedVersion};

  assetIndex = pkgs.fetchurl {
    url = versionData.assetIndex.url;
    sha256 = versionData.assetIndex.sha256;
  };

  activeJvmArgs =
    builtins.filter (
      arg:
        if !(arg ? system)
        then true
        else arg.system == system
    )
    versionData.jvmArgs;
  rawJvmStrings = map (arg: arg.value) activeJvmArgs;
  parsedJvmArgs =
    map (
      arg: let
        subbed1 = nixpkgs.lib.strings.replaceStrings ["\${natives_directory}"] ["\"$GAME_DIR/natives\""] arg;
        subbed2 = nixpkgs.lib.strings.replaceStrings ["\${launcher_name}"] ["nix-launcher"] subbed1;
        subbed3 = nixpkgs.lib.strings.replaceStrings ["\${launcher_version}"] ["1.0"] subbed2;
      in
        nixpkgs.lib.strings.replaceStrings ["\${classpath}"] [""] subbed3
    )
    rawJvmStrings;
  cleanJvmArgs = builtins.filter (x: x != "" && x != "-cp") parsedJvmArgs;
  jvmArgsString = nixpkgs.lib.strings.concatStringsSep " " cleanJvmArgs;

  javaRuntime = pkgs."jdk${toString versionData.javaVersion}";

  vanillaClient = pkgs.fetchurl {
    url = versionData.client.url;
    sha256 = versionData.client.sha256;
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

  allLibraries =
    vanillaLibraries
    ++ [
      vanillaClient
    ];
  classpath = nixpkgs.lib.strings.concatStringsSep ":" allLibraries;

  pythonEnv = pkgs.python3.withPackages (ps: [
    ps.aiohttp
  ]);
in {
  default = pkgs.writeShellApplication {
    name = "minecraft";

    runtimeInputs = [
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
      echo "Launching Minecraft: ${selectedVersion}"
      echo "Instance: ${configName}"
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

  generate-versions = import ../scripts/generate-versions.nix pkgs;
}
