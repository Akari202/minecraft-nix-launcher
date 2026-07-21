import base64
import hashlib
import json
import re
import urllib.request
from dataclasses import dataclass, field
from pprint import pprint
from typing import Any, Dict, Iterator, Optional, Self, Set, Union
from util import *
from enum import StrEnum

# from urllib.parse import quote


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
            "linux": cls.LINUX_X86,
            "osx": cls.MAC_X86,
            "windows": cls.WINDOWS_X86,
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


def match_mojang_rule_to_targets(rule: dict) -> list[Target]:
    os_rules = rule.get("os", {})
    os_name = os_rules.get("name")
    os_arch = os_rules.get("arch")

    matched = set(valid_nix_targets)

    if os_name == "osx":
        matched = {t for t in matched if "darwin" in t.value}
    elif os_name == "linux":
        matched = {t for t in matched if "linux" in t.value}
    elif os_name == "windows":
        matched = {t for t in matched if "windows" in t.value}

    if os_arch == "x86":
        matched = {t for t in matched if "x86_64" in t.value}
    elif os_arch == "arm":
        matched = {t for t in matched if "aarch64" in t.value}

    return list(matched)


@dataclass
class Source:
    url: str
    sha: str
    target: Target = Target.ALL
    path: Optional[str] = None

    def __str__(self) -> str:
        system = "" if self.target == Target.ALL else f'system =  "{self.target}";'
        path = "" if self.path is None else f'path = "{self.path}";'
        return f'{{ url = "{self.url}"; sha256 = "{self.sha}"; {system} {path} }}'

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
        return f'''{format_minecraft_name(self.name)} = {{
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
        return f'''{format_fabric_name(self.name)} = {{
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
