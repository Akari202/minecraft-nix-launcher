{
  description = "Modded Minecraft client on Nix";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);

      versions = import ./pkgs/versions.nix;

      selectedVersion = "Minecraft-1-21-11";

      configName = "testing";
      versionData = versions.versions.${selectedVersion};

      launchConfig = {
        ramMin = "4G";
        ramMax = "8G";
        javaArgs = "-XX:+UseG1GC -XX:MaxGCPauseMillis=200 -XX:+PerfDisableSharedMem -XX:+AlwaysPreTouch";
        username = "Player";
      };
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};

          activeJvmArgs = builtins.filter (
            arg: if !(arg ? system) then true else arg.system == system
          ) versionData.jvmArgs;
          rawJvmStrings = map (arg: arg.value) activeJvmArgs;
          parsedJvmArgs = map (
            arg:
            let
              subbed1 =
                nixpkgs.lib.strings.replaceStrings [ "\${natives_directory}" ] [ "$GAME_DIR/natives" ]
                  arg;
              subbed2 = nixpkgs.lib.strings.replaceStrings [ "\${launcher_name}" ] [ "nix-launcher" ] subbed1;
              subbed3 = nixpkgs.lib.strings.replaceStrings [ "\${launcher_version}" ] [ "1.0" ] subbed2;
              finalString = nixpkgs.lib.strings.replaceStrings [ "\${classpath}" ] [ "" ] subbed3;
            in
            finalString
          ) rawJvmStrings;

          cleanJvmArgs = builtins.filter (x: x != "" && x != "-cp") parsedJvmArgs;
          jvmArgsString = nixpkgs.lib.strings.concatStringsSep " " cleanJvmArgs;

          javaRuntime = pkgs."jdk${toString versionData.javaVersion}";

          vanillaClient = pkgs.fetchurl {
            url = versionData.client.url;
            sha256 = versionData.client.sha256;
          };

          vanillaLibraries = map (
            lib:
            pkgs.fetchurl {
              url = lib.url;
              sha256 = lib.sha256;
              name = builtins.baseNameOf lib.url;
            }
          ) versionData.libraries;

          rawLoggingConfig = pkgs.fetchurl {
            url = versionData.logging.config.url;
            sha256 = versionData.logging.config.sha256;
          };
          loggingConfig = pkgs.runCommand "client-logging.xml" { } ''
            sed 's|fileName="logs/|fileName="\$\{sys:log_dir\}/|g' ${rawLoggingConfig} > $out
          '';
          loggingArgs =
            nixpkgs.lib.strings.replaceStrings [ "\${path}" ] [ "${loggingConfig}" ]
              versionData.logging.args;

          allLibraries = vanillaLibraries ++ [
            vanillaClient
          ];
          classpath = nixpkgs.lib.strings.concatStringsSep ":" allLibraries;
        in
        {
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
        }
      );
    };
}
