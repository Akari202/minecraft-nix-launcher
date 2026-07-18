import logging

logging.basicConfig(format="%(levelname)s: %(message)s", level=logging.INFO)
# logging.basicConfig(format="%(levelname)s: %(message)s", level=logging.DEBUG)
import base64
import hashlib
import json
import re
import urllib.request
from dataclasses import dataclass, field
from typing import Any, Dict, Optional, Set, Union
from util import *
from data import *
from typing import Self

# json_cache.pop("https://piston-meta.mojang.com/mc/game/version_manifest_v2.json")
minecraft_version_manifest = fetch_json_url(
    "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"
)
output_file = OutputFile("pkgs/versions-new.nix")

info("Parsing Minecraft manifest")
minecraft = Minecraft(
    latest=LatestVersion(
        release=minecraft_version_manifest["latest"]["release"],
        snapshot=minecraft_version_manifest["latest"]["snapshot"],
    ),
    versions=[
        MinecraftVersion.from_url(
            i["url"],
        )
        for i in minecraft_version_manifest["versions"]
    ],
)
output_file.write_chunk(str(minecraft))
