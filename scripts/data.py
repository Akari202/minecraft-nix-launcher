import base64
import hashlib
import json
import re
import urllib.request
from dataclasses import dataclass, field
from typing import Any, Dict, Iterator, Optional, Self, Set, Union
from util import *
from enum import StrEnum


class Target(StrEnum):
    ALL = "all"
    LINUX_X86 = "x86_64-linux"
    LINUX_ARM = "aarch64-linux"
    MAC_X86 = "x86_64-darwin"
    MAC_ARM = "aarch64-darwin"
    WINDOWS_X86 = "x86_64-windows"
    UNKNOWN = "unknown"

    @classmethod
    def _missing_(cls, value: object) -> Self:
        if not isinstance(value, str):
            return cls.UNKNOWN

        normalized = value.strip().lower().replace("-", "_")

        reconciliation_map = {
            "linux_x86_64": cls.LINUX_X86,
            "linux_amd64": cls.LINUX_X86,
            "linux_arm64": cls.LINUX_ARM,
            "linux_aarch64": cls.LINUX_ARM,
            "darwin_x86_64": cls.MAC_X86,
            "darwin_amd64": cls.MAC_X86,
            "darwin_arm64": cls.MAC_ARM,
            "darwin_aarch64": cls.MAC_ARM,
            "macos_arm64": cls.MAC_ARM,
            "natives_linux": cls.LINUX_X86,
            "natives_osx": cls.MAC_X86,
            "natives_macos": cls.MAC_X86,
            "natives_windows": cls.WINDOWS_X86,
            "windows_x86_64": cls.WINDOWS_X86,
        }

        if normalized in reconciliation_map:
            return reconciliation_map[normalized]
        else:
            debug(f"'{value}' is not a valid Nix Target.")
            return cls.UNKNOWN


valid_nix_targets = [
    Target.LINUX_X86,
    Target.LINUX_ARM,
    Target.MAC_X86,
    Target.MAC_ARM,
]


@dataclass
class Source:
    url: str
    sha: str
    target: Target
    path: Optional[str] = None

    def __str__(self) -> str:
        systems = (
            ""
            if self.target == Target.ALL
            else f"systems = [ {" ".join(f'"{t}"' for t in self.target)} ];"
        )
        path = "" if self.path is None else f'path = "{self.path}";'
        return f'{{ url = "{self.url}"; sha256 = "{self.sha}"; {systems} {path} }}'

    def __hash__(self) -> int:
        return hash(self.sha)

    @classmethod
    def from_url(
        cls,
        url: str,
        sha: Optional[str] = None,
        target: Target = Target.ALL,
        path: Optional[str] = None,
    ) -> Self:
        if sha is None:
            fixed_sha = get_sha_from_url(url)
        else:
            if sha_is_hex(sha):
                fixed_sha = format_sha(
                    base64.b64encode(bytes.fromhex(sha)).decode("utf-8")
                )
            else:
                fixed_sha = format_sha(sha)
            sha_cache[url] = fixed_sha
        return cls(url=url, sha=fixed_sha, target=target, path=path)


@dataclass
class Logging:
    args: str
    config: Source

    def __str__(self) -> str:
        return f'{{ args = "{self.args}"; config = {self.config}; }}'


@dataclass
class MinecraftVersion:
    name: str
    client: Source
    server: Optional[Source]
    javaVersion: Optional[int]
    clientMainClass: str
    logging: Optional[Logging]
    libraries: set[Source]

    def __str__(self) -> str:
        return f'''{format_name(self.name)} = {{
  client = {self.client};
  server = {optional_to_nix(self.server)};
  javaVersion = {optional_to_nix(self.javaVersion)};
  clientMainClass = "{self.clientMainClass}";
  logging = {optional_to_nix(self.logging)};
  libraries = [
    {"\n    ".join(str(lib) for lib in self.libraries)}
  ];
}};'''

    @classmethod
    def from_url(cls, url: str) -> Self:
        def get_library_sources(data: Dict[str, Any]) -> Iterator[Source]:
            if "artifact" in data:
                yield Source.from_url(
                    data["artifact"]["url"], path=data["artifact"]["path"]
                )

            elif "classifiers" in data:
                for i, j in data["classifiers"].items():
                    yield Source.from_url(j["url"], target=Target(i), path=j["path"])

            else:
                error(f"Unknown library data format: {data}")

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
                    args=i["client"]["argument"].replace("${path}", "\\${path}"),
                    config=Source.from_url(i["client"]["file"]["url"]),
                ),
            ),
            libraries=set(
                [
                    j
                    for i in data["libraries"]
                    for j in get_library_sources(i["downloads"])
                    if j.target in valid_nix_targets or j.target == Target.ALL
                ]
            ),
        )


@dataclass
class LatestVersion:
    release: str
    snapshot: str

    def __str__(self) -> str:
        return f'{{ release = "{format_name(self.release)}"; snapshot = "{format_name(self.snapshot)}"; }}'


@dataclass
class Minecraft:
    latest: LatestVersion
    versions: list[MinecraftVersion]

    def __str__(self) -> str:
        return f'''{{
  latest = {self.latest};
  versions = {{
    {"\n  ".join(str(v) for v in self.versions)}
  }};
}}'''
