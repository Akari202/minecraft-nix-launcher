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
  sources = import ./sources.nix {inherit pkgs nixpkgs versionData fabricLoaderData isFabric;};
  resolvedMods = import ./mods.nix {inherit pkgs minecraftVersion gameConfig;};
in {
  default = import ./client.nix {
    inherit pkgs nixpkgs configName minecraftVersion gameConfig versionData fabricLoaderData isFabric jvmArgsString sources resolvedMods javaRuntime;
  };

  minecraft-server = import ./server.nix {
    inherit pkgs nixpkgs configName minecraftVersion gameConfig fabricLoaderData isFabric sources serverPropertiesFile serverLists serverIcon resolvedMods javaRuntime;
  };

  generate-versions = import ./generate-versions.nix pkgs;
}
