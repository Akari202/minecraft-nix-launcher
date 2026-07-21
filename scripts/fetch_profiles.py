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

info("Parsing Fabric manifest")
fabric = Fabric.from_url("https://meta.fabricmc.net/v2/versions/loader/26.2")
info("Writing Fabric versions")
OutputFile("pkgs/fabric-versions-new.nix").write_chunk(str(fabric))

info("Writing caches to disk")
