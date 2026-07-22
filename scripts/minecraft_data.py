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
class JvmArg:
    value: str
    target: Target = Target.ALL

    def __str__(self) -> str:
        system = "" if self.target == Target.ALL else f'system =  "{self.target}";'
        return f'{{ value = "{self.value}"; {system} }}'


@dataclass
class Logging:
    args: str
    config: Source

    def __str__(self) -> str:
        return f'{{ args = "{self.args}"; config = {self.config}; }}'


@dataclass
class AssetIndex:
    name: str
    index: Source

    def __str__(self) -> str:
        return f'{{ id = "{self.name}"; url = "{self.index.url}"; sha256 = "{self.index.sha}"; }}'


@dataclass
class MinecraftVersion:
    name: str
    client: Source
    server: Optional[Source]
    javaVersion: Optional[int]
    clientMainClass: str
    logging: Optional[Logging]
    jvmArgs: list[JvmArg]
    libraries: set[Source]
    assetIndex: str
    fabricIntermediary: Optional[Source]

    def __str__(self) -> str:
        return f'''"{format_minecraft_name(self.name)}" = {{
  client = {self.client};
  version = "{self.name}";
  server = {optional_to_nix(self.server)};
  javaVersion = {optional_to_nix(self.javaVersion)};
  clientMainClass = "{self.clientMainClass}";
  logging = {optional_to_nix(self.logging)};
  fabricIntermediary = {optional_to_nix(self.fabricIntermediary)};
  assetIndex = {self.assetIndex};
  jvmArgs = [
    {"\n    ".join(str(arg) for arg in self.jvmArgs)}
  ];
  libraries = [
    {"\n    ".join(str(lib) for lib in self.libraries)}
  ];
}};'''

    @classmethod
    def from_url(cls, url: str) -> Self:
        def get_library_sources(data: Dict[str, Any]) -> Iterator[Source]:
            downloads = data["downloads"]
            if "artifact" in downloads:
                yield Source.from_url(
                    downloads["artifact"]["url"], path=downloads["artifact"]["path"]
                )

            elif "classifiers" in downloads:
                for i, j in downloads["classifiers"].items():
                    yield Source.from_url(j["url"], target=Target(i), path=j["path"])

            else:
                error(f"Unknown library data format: {data}")

        def get_jvm_args(data: Union[Dict[str, Any], str]) -> Iterator[JvmArg]:
            if isinstance(data, str):
                yield JvmArg(value=data.replace("$", "\\$"))
            else:
                for i in data["rules"]:
                    assert i["action"] == "allow"
                    for j in match_mojang_rule_to_targets(i):
                        yield JvmArg(
                            value=value_or_squish(data["value"]).replace("$", "\\$"),
                            target=j,
                        )

        def get_intermediary(name: str) -> Optional[Source]:
            data = fetch_json_url(
                f"https://meta.fabricmc.net/v2/versions/intermediary/{name.replace(" ", "%20")}"
            )
            if len(data) == 0:
                return None
            else:
                assert len(data) == 1
                return Source.from_url(maven_to_url(maven_name=data[0]["maven"]))

        data = fetch_json_url(url)
        return cls(
            name=data["id"],
            client=Source.from_url(data["downloads"]["client"]["url"]),
            server=extract_field(
                data["downloads"], "server", lambda i: Source.from_url(i["url"])
            ),
            javaVersion=extract_field(data, "javaVersion", lambda i: i["majorVersion"]),
            clientMainClass=data["mainClass"],
            logging=extract_field(
                data,
                "logging",
                lambda i: Logging(
                    args=i["client"]["argument"].replace("$", "\\$"),
                    config=Source.from_url(i["client"]["file"]["url"]),
                ),
            ),
            jvmArgs=extract_field(
                data,
                "arguments",
                lambda i: [
                    k
                    for j in i["jvm"]
                    for k in get_jvm_args(j)
                    if k.target in valid_nix_targets or k.target == Target.ALL
                ],
                default=[],
            ),
            libraries=set(
                [
                    j
                    for i in data["libraries"]
                    for j in get_library_sources(i)
                    if j.target in valid_nix_targets or j.target == Target.ALL
                ]
            ),
            assetIndex=AssetIndex(
                name=data["assets"], index=Source.from_url(data["assetIndex"]["url"])
            ),
            fabricIntermediary=get_intermediary(data["id"]),
        )


@dataclass
class LatestVersion:
    release: str
    snapshot: str

    def __str__(self) -> str:
        return f'{{ release = "{format_minecraft_name(self.release)}"; snapshot = "{format_minecraft_name(self.snapshot)}"; }}'


@dataclass
class Minecraft:
    latest: LatestVersion
    versions: list[MinecraftVersion]

    def __str__(self) -> str:
        return f'''{{
  latest = {self.latest};
  versions = {{
    {"\n  ".join(str(ver) for ver in self.versions)}
  }};
}}'''

    @classmethod
    def from_url(cls, url: str) -> Self:
        data = fetch_json_url(url)
        return cls(
            latest=LatestVersion(
                release=data["latest"]["release"],
                snapshot=data["latest"]["snapshot"],
            ),
            versions=[
                MinecraftVersion.from_url(
                    i["url"],
                )
                for i in data["versions"]
            ],
        )
