{
  description = "Modded Minecraft client on Nix";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
  };

  outputs = {
    self,
    nixpkgs,
  }: let
    selectedVersion = "Minecraft-1-21-11";
    configName = "testing";
    launchConfig = {
      ramMin = "4G";
      ramMax = "8G";
      javaArgs = "-XX:+UseG1GC -XX:MaxGCPauseMillis=200 -XX:+PerfDisableSharedMem -XX:+AlwaysPreTouch";
      username = "Player";
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

      generate-versions = {
        type = "app";
        program = "${self.packages.${system}.generate-versions}/bin/generate-versions";
      };
    });

    packages = forAllSystems (
      system:
        import ./pkgs/builder.nix {
          inherit nixpkgs system selectedVersion configName launchConfig;
        }
    );
  };
}
