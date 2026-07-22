{
  pkgs,
  nixpkgs,
  versionData,
  fabricLoaderData,
  isFabric,
}: let
  fetchSource = lib:
    pkgs.fetchurl {
      url = lib.url;
      sha256 = lib.sha256;
      name = builtins.baseNameOf lib.url;
    };

  sharedLibraries =
    (map fetchSource versionData.libraries)
    ++ (
      if isFabric
      then
        (map fetchSource fabricLoaderData.commonLibraries)
        ++ [(fetchSource fabricLoaderData.loader)]
        ++ [(fetchSource versionData.fabricIntermediary)]
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
in {
  assetIndex = fetchSource versionData.assetIndex;
  clientClasspath = nixpkgs.lib.strings.concatStringsSep ":" clientLibraries;
  serverClasspath = nixpkgs.lib.strings.concatStringsSep ":" serverLibraries;
  loggingArgs = nixpkgs.lib.strings.replaceStrings ["\${path}"] ["${loggingConfig}"] versionData.logging.args;
}
