{
  pkgs,
  minecraftVersion,
  gameConfig,
}: let
  lib = pkgs.lib;
  modrinthData = import ../pkgs/modrinth-versions.nix;

  parsedUserMods = map (
    mod:
      if builtins.isString mod
      then {
        name = mod;
        version = null;
      }
      else {
        name = mod.name;
        version = mod.version or null;
      }
  ) (gameConfig.mods or []);

  resolveMod = userMod: let
    modName = userMod.name;
    allVersions = modrinthData.${modName} or (throw "Mod ${modName} not found");

    compatibleVersions =
      lib.filterAttrs (
        versionKey: value:
          builtins.elem minecraftVersion (value.minecraftVersions or [])
      )
      allVersions;

    _validate =
      if compatibleVersions == {}
      then throw "No compatible versions found for ${modName} matching Minecraft version ${minecraftVersion}"
      else true;

    sortedKeys = lib.sort (
      a: b: let
        dateA = compatibleVersions.${a}.datePublished;
        dateB = compatibleVersions.${b}.datePublished;
      in
        dateA > dateB
    ) (builtins.attrNames compatibleVersions);

    latestKey = builtins.head sortedKeys;

    selectedVersionInfo =
      if userMod.version != null
      then allVersions.${userMod.version} or (throw "Explicit version ${userMod.version} for ${modName} not found")
      else compatibleVersions.${latestKey};

    modFile = builtins.head selectedVersionInfo.files;
  in
    pkgs.fetchurl {
      url = modFile.url;
      sha256 = modFile.sha256;
      name = "${modName}-${selectedVersionInfo.name}.jar";
    };
in
  map resolveMod parsedUserMods
