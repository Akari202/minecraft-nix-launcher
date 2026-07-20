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

info("Parsing Minecraft manifest")
minecraft = Minecraft.from_url(
    "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"
)
info("Writing Minecraft versions")
OutputFile("pkgs/versions-new.nix").write_chunk(str(minecraft))

info("Parsing asset indexes")
assets = [AssetIndex.from_url(name=i, url=j) for i, j in asset_index_cache.items()]
info("Writing asset versions")
asset_output_file = OutputFile("pkgs/asset-versions-new.nix")
asset_output_file.write("{")
for ass in assets:
    asset_output_file.write("\n  ")
    asset_output_file.write_chunk(str(ass))

asset_output_file.write_chunk("}")
info("Writing caches to disk")
