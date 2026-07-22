import base64
import hashlib
import json
import logging
import re
import urllib.request
from dataclasses import dataclass, field
from logging import debug, error, info, warning
from pprint import pprint
from typing import Any, Dict, Iterator, Optional, Self, Set, Union
from util import *
from data import *
from enum import StrEnum
from logging import debug, error, info, warning
from pprint import pprint
from urllib.parse import quote


@dataclass
class ModVersion:
    ident: str
    name: str
    version: str
    datePublished: str
    files: list[Source]
    minecraftVersions: list[str]

    def __hash__(self) -> int:
        return hash(self.ident)

    def __eq__(self, other):
        if not isinstance(other, ModVersion):
            return False
        return self.ident == other.ident

    def __str__(self) -> str:
        return f'''"{self.version}-{self.ident}" = {{
  name = "{self.name}";
  datePublished = "{self.datePublished}";
  minecraftVersions = [
    {"\n    ".join(f'"{ver}"' for ver in self.minecraftVersions)}
  ];
  files = [
    {"\n    ".join(str(fil) for fil in self.files)}
  ];
}};'''


@dataclass
class Mod:
    name: str
    versions: list[ModVersion]

    def __str__(self) -> str:
        return f'''"{self.name}" = {{
  {"\n    ".join(str(ver) for ver in self.versions)}
}};'''

    @classmethod
    def from_name(cls, name: str) -> Self:
        info(f"Fetching mod versions of {name}")
        data = get_fabric_mod_versions(name)
        recent_data = sorted(
            data, key=lambda x: x.get("date_published", ""), reverse=True
        )[:500]
        return cls(
            name=name,
            versions=[
                ModVersion(
                    ident=i["id"],
                    name=i["name"],
                    datePublished=i["date_published"],
                    version=i["version_number"],
                    files=[Source.from_url(j["url"]) for j in i["files"]],
                    minecraftVersions=[
                        format_minecraft_name(j) for j in i["game_versions"]
                    ],
                )
                for i in recent_data
            ],
        )


@dataclass
class ModrinthMods:
    mods: list[Mod]

    def __str__(self) -> str:
        return f'''{{
  {"\n    ".join(str(mod) for mod in self.mods)}
}}'''

    @classmethod
    def from_name_list(cls, names: list[str]) -> Self:
        return cls(mods=[Mod.from_name(i) for i in names])
