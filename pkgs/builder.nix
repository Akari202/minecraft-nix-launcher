{
  nixpkgs,
  system,
  selectedVersion,
  configName,
  launchConfig,
}: let
  pkgs = nixpkgs.legacyPackages.${system};
  versions = import ./versions.nix;
  assetVersions = import ./asset-versions.nix;
  versionData = versions.versions.${selectedVersion};
  assetData = assetVersions.${versionData.assetIndex};

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
        subbed1 = nixpkgs.lib.strings.replaceStrings ["\${natives_directory}"] ["$GAME_DIR/natives"] arg;
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
    sed 's|fileName="logs/|fileName="\$\{sys:log_dir\}/|g' ${rawLoggingConfig} > $out
  '';
  loggingArgs = nixpkgs.lib.strings.replaceStrings ["\${path}"] ["${loggingConfig}"] versionData.logging.args;

  allLibraries =
    vanillaLibraries
    ++ [
      vanillaClient
    ];
  classpath = nixpkgs.lib.strings.concatStringsSep ":" allLibraries;
in {
  default = pkgs.writeShellScriptBin "minecraft" ''
    set -euo pipefail

    GAME_DIR="''${GAME_DIR:-$HOME/.minecraft-nix-instances/${configName}}"
    mkdir -p "$GAME_DIR"
    MODS_DIR="$GAME_DIR/mods"
    mkdir -p "$MODS_DIR"
    LOGS_DIR="$GAME_DIR/logs"
    mkdir -p "$LOGS_DIR"

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
      -Dlog_dir=$LOGS_DIR \
      -cp "${classpath}" \
      ${versionData.clientMainClass} \
      --gameDir "$GAME_DIR" \
      --username "${launchConfig.username}" \
      --version "${versionData.version}" \
      --versionType "release" \
      --assetsDir "$GAME_DIR/assets" \
      --uuid "00000000-0000-0000-0000-000000000000" \
      --accessToken "0" \
      "$@"
  '';

  generate-versions = import ../scripts/generate-versions.nix pkgs;
}
