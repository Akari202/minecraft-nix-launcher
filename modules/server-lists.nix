{
  pkgs,
  userLists ? {},
}: let
  mkPlayer = name: {
    uuid = "00000000-0000-0000-0000-000000000000";
    inherit name;
  };

  mkOp = name:
    (mkPlayer name)
    // {
      level = 4;
      bypassesPlayerLimit = false;
    };

  mkBannedPlayer = name:
    (mkPlayer name)
    // {
      created = "2026-07-20 00:00:00 -0000";
      source = "Nix config";
      expires = "forever";
      reason = "Banned via Nix configuration";
    };

  mkBannedIp = ip: {
    inherit ip;
    created = "2026-07-20 00:00:00 -0000";
    source = "Nix config";
    expires = "forever";
    reason = "Banned via Nix configuration";
  };

  opsList = map mkOp (userLists.ops or []);
  whiteList = map mkPlayer (userLists.whitelist or []);
  bannedPlayers = map mkBannedPlayer (userLists.banned-players or []);
  bannedIps = map mkBannedIp (userLists.banned-ips or []);
in {
  opsFile = pkgs.writeText "ops.json" (builtins.toJSON opsList);
  whitelistFile = pkgs.writeText "whitelist.json" (builtins.toJSON whiteList);
  bannedPlayersFile = pkgs.writeText "banned-players.json" (builtins.toJSON bannedPlayers);
  bannedIpsFile = pkgs.writeText "banned-ips.json" (builtins.toJSON bannedIps);
}
