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
from typing import Self


@dataclass
class Source:
    url: str
    sha: str

    def __str__(self) -> str:
        return f'{{ url = "{self.url}"; sha256 = "{self.sha}"; }}'

    @classmethod
    def from_url(cls, url: str, sha: Optional[str] = None) -> Self:
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
        return cls(url=url, sha=fixed_sha)


@dataclass
class FabricVersion:
    name: str
    source: Source
    intermediary: Source
    clientMainClass: str
    serverMainClass: str
    clientLibraries: list[Source]
    serverLibraries: list[Source]
    commonLibraries: list[Source]

    def __str__(self) -> str:
        def format_list(libs):
            if not libs:
                return "[ ]"
            items = "".join(f"\n    {lib}" for lib in libs)
            return f"[{items}\n  ]"

        return (
            f'"{self.name}" = {{\n'
            f"  source = {self.source};\n"
            f"  intermediary = {self.intermediary};\n"
            f'  clientMainClass = "{self.clientMainClass}";\n'
            f'  serverMainClass = "{self.serverMainClass}";\n'
            f"  clientLibraries = {format_list(self.clientLibraries)};\n"
            f"  serverLibraries = {format_list(self.serverLibraries)};\n"
            f"  commonLibraries = {format_list(self.commonLibraries)};\n"
            f"}};"
        )


@dataclass
class Version:
    name: str
    client: Optional[Source]
    server: Optional[Source]
    javaVersion: int
    fabricVersions: Optional[list[FabricVersion]]

    def __str__(self) -> str:
        def format_opt(val):
            return f'"{val}"' if isinstance(val, str) else str(val) if val else "null"

        def format_fabrics(fabrics):
            if fabrics is None:
                return "null"
            if not fabrics:
                return "{ }"
            items = "".join(f"\n{str(f).replace('\n', '\n  ')}" for f in fabrics)
            return f"{{{items}\n}}"

        return (
            f'"{self.name}" = {{\n'
            f"  javaVersion = {self.javaVersion};\n"
            f"  client = {format_opt(self.client)};\n"
            f"  server = {format_opt(self.server)};\n"
            f"  fabricVersions = {format_fabrics(self.fabricVersions)};\n"
            f"}};"
        )


minecraft_versions_table_url = "https://gist.githubusercontent.com/cliffano/77a982a7503669c3e1acb0a0cf6127e9/raw/f0f4e1afa6c7a887dd6aadb9ebaeebec293b1686/minecraft-server-jar-downloads.md"
minecraft_versions_table = "./scripts/versions.md"
output_file = "pkgs/versions-new.nix"
version_java_cache = DiskDict(filename="./scripts/version_java_cache.json")


def get_fabric_data_for_version(minecraft_version: str) -> list[FabricVersion]:
    def get_main_class(main_class: Union[dict, str], kind: str) -> str:
        if isinstance(main_class, str):
            return main_class
        else:
            return main_class[kind]

    def resolve_library_url(lib: dict) -> str:
        if lib["name"] == "net.minecraft:launchwrapper:1.12":
            return "https://libraries.minecraft.net/"
        else:
            return lib["url"]

    info(f"Getting fabric data for version {minecraft_version}")
    meta_url = f"https://meta.fabricmc.net/v2/versions/loader/{minecraft_version}"
    req = urllib.request.Request(meta_url, headers=headers)
    with urllib.request.urlopen(req) as response:
        debug("Parsing version data")
        data = json.loads(response.read().decode("utf-8"))
        return [
            FabricVersion(
                name=i["loader"]["version"],
                source=Source.from_url(
                    maven_to_url(i["loader"]["maven"], "https://maven.fabricmc.net/")
                ),
                intermediary=Source.from_url(
                    maven_to_url(
                        i["intermediary"]["maven"], "https://maven.fabricmc.net/"
                    )
                ),
                clientMainClass=get_main_class(
                    i["launcherMeta"]["mainClass"], "client"
                ),
                serverMainClass=get_main_class(
                    i["launcherMeta"]["mainClass"], "server"
                ),
                clientLibraries=[
                    Source.from_url(
                        maven_to_url(j["name"], resolve_library_url(j)),
                        sha=j.get("sha256"),
                    )
                    for j in i["launcherMeta"]["libraries"]["client"]
                ],
                serverLibraries=[
                    Source.from_url(
                        maven_to_url(j["name"], resolve_library_url(j)),
                        sha=j.get("sha256"),
                    )
                    for j in i["launcherMeta"]["libraries"]["server"]
                ],
                commonLibraries=[
                    Source.from_url(
                        maven_to_url(j["name"], resolve_library_url(j)),
                        sha=j.get("sha256"),
                    )
                    for j in i["launcherMeta"]["libraries"]["common"]
                ],
            )
            for i in data
        ]


try:
    with open(minecraft_versions_table, "r") as file:
        info("Using cached Minecraft versions table")
except FileNotFoundError:
    info("Retrieving Minecraft versions table")
    urllib.request.urlretrieve(minecraft_versions_table_url, minecraft_versions_table)

info("Parsing Minecraft version table")
row_pattern = re.compile(r"^\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|\s*$")
with open(output_file, "w") as file:
    file.write("{")
with open(minecraft_versions_table, "r") as file:
    try:
        for line in file.readlines()[2:]:
            match = row_pattern.match(line)
            if match:
                version = match.group(1).strip()
                server_url = match.group(2).strip()
                client_url = match.group(3).strip()
                fabric_versions = get_fabric_data_for_version(version)
                client = None
                server = None
                if client_url != "Not found":
                    client = Source.from_url(client_url)
                if server_url != "Not found":
                    server = Source.from_url(server_url)
                version = Version(
                    name=version,
                    javaVersion=version_java_cache.setdefault(version, 0),
                    client=client,
                    server=server,
                    fabricVersions=fabric_versions,
                )
                info(f"Writing {output_file}")
                with open(output_file, "a") as file:
                    file.write(str(version))
    except KeyboardInterrupt:
        pass
    finally:
        with open(output_file, "a") as file:
            file.write("}")
