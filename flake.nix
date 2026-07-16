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

      versions = import ./pkgs/versions-tmp.nix;

      selectedVersion = "1.21.11";
      selectedFabricVersion = "0.19.3";

      configName = "testing";
      versionData = versions.${selectedVersion};
      fabricVersionData = versionData.fabricVersions.${selectedFabricVersion};

      launchConfig = {
        ramMin = "4G";
        ramMax = "8G";
        javaArgs = "-XX:+UseG1GC -XX:MaxGCPauseMillis=200 -XX:+PerfDisableSharedMem -XX:+AlwaysPreTouch -DFabricMcEmu=net.minecraft.client.main.Main";
        username = "Player";
      };
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};

          javaRuntime = pkgs."jdk${toString versionData.javaVersion}";

          localClientJar = ./jars/client-${selectedVersion}.jar;
          vanillaClient =
            if builtins.pathExists localClientJar then
              localClientJar
            else
              pkgs.fetchurl {
                url = versionData.client.url;
                sha256 = versionData.client.sha256;
                timeout = 3600;
              };

          localFabricJar = ./jars/fabric-loader-${selectedFabricVersion}.jar;
          fabricLoader =
            if builtins.pathExists localFabricJar then
              localFabricJar
            else
              pkgs.fetchurl {
                url = fabricVersionData.source.url;
                sha256 = fabricVersionData.source.sha256;
              };

          intermediary = pkgs.fetchurl {
            url = fabricVersionData.intermediary.url;
            sha256 = fabricVersionData.intermediary.sha256;
          };

          commonLibraries = map (
            lib:
            pkgs.fetchurl {
              url = lib.url;
              sha256 = lib.sha256;
              name = builtins.baseNameOf lib.url;
            }
          ) fabricVersionData.commonLibraries;

          clientLibraries = map (
            lib:
            pkgs.fetchurl {
              url = lib.url;
              sha256 = lib.sha256;
              name = builtins.baseNameOf lib.url;
            }
          ) fabricVersionData.clientLibraries;

          allLibraries =
            commonLibraries
            ++ clientLibraries
            ++ [
              fabricLoader
              intermediary
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

            echo "Username: ${launchConfig.username}"
            echo "Instance: ${configName}"
            echo "Launching Minecraft: ${selectedVersion}"
            echo "Using Fabric: ${selectedFabricVersion}"
            echo "Instance: ${configName}"
            echo "Game Directory: $GAME_DIR"
            echo "Java Version: ${javaRuntime.version}"
            echo "Memory: ${launchConfig.ramMin} - ${launchConfig.ramMax}"
            echo ""

            exec ${javaRuntime}/bin/java \
              -Xms${launchConfig.ramMin} \
              -Xmx${launchConfig.ramMax} \
              ${launchConfig.javaArgs} \
              -cp "${classpath}" \
              ${fabricVersionData.clientMainClass} \
              --gameDir "$GAME_DIR" \
              --username "${launchConfig.username}" \
              --versionType "release" \
              "$@"
          '';
        }
      );
    };
}
