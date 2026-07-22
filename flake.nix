{
  description = "Modded Minecraft client on Nix";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
  };

  outputs = {
    self,
    nixpkgs,
  }: let
    minecraftVersion = "Minecraft 1.21.11";
    configName = "testing";
    gameConfig = {
      fabricLoaderVersion = "Fabric 0.19.3";

      mods = [
        "sodium"
        "lithium"
        "sodium-extra"
        "malilib"
        "tweakeroo"
        "litematica"
        "minihud"
        "item-scroller"
        "servux"
        "fabric-api"
        "appleskin"
        "continuity"
        "distanthorizons"
        "lambdynamiclights"
        "modmenu"
        "ambientsounds"
        "no-chat-reports"
        "reeses-sodium-options"
        "xaeros-world-map"
        "ferrite-core"
        "creativecore"
        "immediatelyfast"
        "calcmod"
        "cull-leaves"
        "krypton"
        "carpet"
        "carpet-extra"
        "sound-physics-remastered"
        "entityculling"
        "3dskinlayers"
      ];

      launchConfig = {
        ramMin = "2G";
        ramMax = "6G";
        javaArgs = "-XX:+UseZGC -XX:+ZUncommit -XX:ZUncommitDelay=300 -XX:+UseStringDeduplication -XX:+UseNUMA -XX:MaxGCPauseMillis=200 -XX:+PerfDisableSharedMem -XX:+AlwaysPreTouch";
        # javaArgs = "-XX:+UseG1GC -XX:+UseStringDeduplication -XX:+UseNUMA -XX:MaxGCPauseMillis=200 -XX:+PerfDisableSharedMem -XX:+AlwaysPreTouch";
        username = "Player";
      };

      serverProperties = {
        motd = "Testing, launched with Nix!";
      };

      serverLists = {
        ops = ["Player"];
      };
    };

    systems = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
    forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
  in {
    apps = forAllSystems (system: {
      default = self.apps.${system}.minecraft;

      minecraft = {
        type = "app";
        program = "${self.packages.${system}.default}/bin/minecraft";
      };

      minecraft-server = {
        type = "app";
        program = "${self.packages.${system}.minecraft-server}/bin/minecraft-server";
      };

      generate-versions = {
        type = "app";
        program = "${self.packages.${system}.generate-versions}/bin/generate-versions";
      };
    });

    packages = forAllSystems (
      system:
        import ./modules/builder.nix {
          inherit nixpkgs system minecraftVersion configName gameConfig;
        }
    );
  };
}
