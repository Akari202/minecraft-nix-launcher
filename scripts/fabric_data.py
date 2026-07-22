import base64
import hashlib
import json
import re
import urllib.request
from dataclasses import dataclass, field
from pprint import pprint
from typing import Any, Dict, Iterator, Optional, Self, Set, Union
from util import *
from data import *
from enum import StrEnum


@dataclass
class FabricLoader:
    name: str
    loader: Source
    clientMainClass: str
    serverMainClass: str
    clientLibraries: list[Source]
    serverLibraries: list[Source]
    commonLibraries: list[Source]

    def __str__(self) -> str:
        return f'''"{format_fabric_name(self.name)}" = {{
  loader = {self.loader};
  clientMainClass = "{self.clientMainClass}";
  serverMainClass = "{self.serverMainClass}";
  clientLibraries = [
    {"\n    ".join(str(lib) for lib in self.clientLibraries)}
  ];
  serverLibraries = [
    {"\n    ".join(str(lib) for lib in self.serverLibraries)}
  ];
  commonLibraries = [
    {"\n    ".join(str(lib) for lib in self.commonLibraries)}
  ];
}};'''


@dataclass
class Fabric:
    loaders: list[FabricLoader]

    def __str__(self) -> str:
        return f'''{{
    {"\n  ".join(str(loa) for loa in self.loaders)}
}}'''

    @classmethod
    def from_url(cls, url: str) -> Self:
        def get_main_class(data: Union[Dict[str, Any], str], side: str) -> str:
            if isinstance(data, str):
                return data
            else:
                return data[side]

        data = fetch_json_url(url)
        return cls(
            loaders=[
                FabricLoader(
                    name=i["loader"]["version"],
                    loader=Source.from_url(maven_to_url(i["loader"]["maven"])),
                    clientMainClass=get_main_class(
                        i["launcherMeta"]["mainClass"], "client"
                    ),
                    serverMainClass=get_main_class(
                        i["launcherMeta"]["mainClass"], "server"
                    ),
                    clientLibraries=[
                        Source.from_url(
                            maven_to_url(maven_name=j["name"], base_url=j["url"])
                        )
                        for j in i["launcherMeta"]["libraries"]["client"]
                    ],
                    serverLibraries=[
                        Source.from_url(
                            maven_to_url(maven_name=j["name"], base_url=j["url"])
                        )
                        for j in i["launcherMeta"]["libraries"]["server"]
                    ],
                    commonLibraries=[
                        Source.from_url(
                            maven_to_url(
                                maven_name=j["name"],
                                base_url=j.get(
                                    "url", "https://libraries.minecraft.net"
                                ),
                            )
                        )
                        for j in i["launcherMeta"]["libraries"]["common"]
                    ],
                )
                for i in data
            ]
        )
