{
  system,
  nixpkgs,
  jvmArgs,
}: let
  activeJvmArgs =
    builtins.filter (
      arg:
        if !(arg ? system)
        then true
        else arg.system == system
    )
    jvmArgs;

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
in
  nixpkgs.lib.strings.concatStringsSep " " cleanJvmArgs
