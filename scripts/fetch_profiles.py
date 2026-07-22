import logging

logging.basicConfig(format="%(levelname)s: %(message)s", level=logging.INFO)
# logging.basicConfig(format="%(levelname)s: %(message)s", level=logging.DEBUG)
import base64
import hashlib
import json
import re
import urllib.request
from dataclasses import dataclass, field
from logging import debug, error, info, warning
from typing import Any, Dict, Optional, Self, Set, Union

from fabric_data import Fabric
from minecraft_data import Minecraft
from mod_data import ModrinthMods
from output_file import OutputFile
from util import json_cache

# json_cache.pop("https://piston-meta.mojang.com/mc/game/version_manifest_v2.json")
# json_cache.pop("https://meta.fabricmc.net/v2/versions/loader/26.2")
# modrinth_json_cache.clear()

info("Parsing Minecraft manifest")
minecraft = Minecraft.from_url(
    "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"
)
info("Writing Minecraft versions")
OutputFile("pkgs/versions-new.nix").write_chunk(str(minecraft))

info("Parsing Fabric manifest")
fabric = Fabric.from_url("https://meta.fabricmc.net/v2/versions/loader/26.2")
info("Writing Fabric versions")
OutputFile("pkgs/fabric-versions-new.nix").write_chunk(str(fabric))

info("Fetching mod data")
included_mods = set(
    [
        "sodium",
        "sodium-extra",
        "lithium",
        "malilib",
        "tweakeroo",
        "litematica",
        "minihud",
        "item-scroller",
        "servux",
        "fabric-api",
        "appleskin",
        "continuity",
        "distanthorizons",
        "lambdynamiclights",
        "modmenu",
        "krypton",
        "simple-voice-chat",
        "entityculling",
        "carpet",
        "carpet-extra",
        "ambientsounds",
        "creativecore",
        "no-chat-reports",
        "reeses-sodium-options",
        "3dskinlayers",
        "sound-physics-remastered",
        "xaeros-world-map",
        "ferrite-core",
        "immediatelyfast",
        "calcmod",
        "cull-leaves",
    ]
)
modrinth_mods = ModrinthMods.from_name_list(included_mods)
info("Writing mod versions")
OutputFile("pkgs/modrinth-versions-new.nix").write_chunk(str(modrinth_mods))

info("Writing caches to disk")
