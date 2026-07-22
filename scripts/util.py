import base64
import hashlib
import json
import re
import urllib.request
from dataclasses import dataclass, field
from logging import debug, error, info, warning
from typing import Any, Callable, Dict, Optional, Set, TypeVar, Union

from disk_dict import DiskDict
from output_file import OutputFile

sha_cache = DiskDict(filename="./scripts/cache/sha_cache.json")
json_cache = DiskDict(filename="./scripts/cache/json_cache.json")
modrinth_json_cache = DiskDict(filename="./scripts/cache/modrinth_json_cache.json")
headers = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X x.y; rv:10.0) Gecko/20100101 Firefox/10.0 (akari202@akada.dev)"
}
modrinth_headers = {
    "User-Agent": "Akari202/minecraft-nix-launcher (akari202@akada.dev)"
}
modrinth_query_string = urllib.parse.urlencode(
    {"loaders": '["fabric"]', "include_changelog": "false"}
)

T = TypeVar("T")


def optional_to_nix(data: Optional[T]) -> str:
    if data is None:
        return "null"
    else:
        return str(data)


def format_minecraft_name(name: str) -> str:
    return f"Minecraft {name}"


def format_fabric_name(name: str) -> str:
    return f"Fabric {name}"


def value_or_squish(
    data: Union[list[str], tuple[str], str], separator: str = " "
) -> str:
    if isinstance(data, (list, tuple)):
        return separator.join(data)
    else:
        return data


def extract_field(
    data: Dict[str, Any], key: str, builder: Callable[[Any], T], default: Any = None
) -> Optional[T]:
    inner = data.get(key)
    if inner is None:
        return default
    return builder(inner)


def upgrade_to_https(url: str) -> str:
    return url.replace("http://", "https://")


def fetch_json_url(url: str) -> Dict[str, Any]:
    url = upgrade_to_https(url)
    debug(f"Getting json for {url}")
    json_data = json_cache.get(url)
    if json_data is None:
        info(f"Fetching fresh json from {url}")
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req) as response:
            json_data = json.loads(response.read().decode("utf-8").strip())
        json_cache[url] = json_data
    else:
        debug(f"Using cached json")
    return json_data


def get_fabric_mod_versions(mod_id_or_slug: str) -> Dict[str, Any]:
    url = f"https://api.modrinth.com/v2/project/{mod_id_or_slug}/version?{modrinth_query_string}"
    debug(f"Getting json for {url}")
    json_data = modrinth_json_cache.get(url)
    if json_data is None:
        info(f"Fetching fresh json from {url}")
        req = urllib.request.Request(url, headers=modrinth_headers)
        with urllib.request.urlopen(req) as response:
            json_data = json.loads(response.read().decode("utf-8").strip())
        modrinth_json_cache[url] = json_data
    else:
        debug(f"Using cached json")
    return json_data


def sha_is_hex(sha):
    return bool(re.match(r"^sha256-[a-fA-F0-9]+=$", format_sha(sha)))


def format_sha(sha: str) -> str:
    if not sha.startswith("sha256-"):
        sha = f"sha256-{sha}"
    if not sha.endswith("="):
        sha = f"{sha}="
    return sha


def try_sidecar_url(url: str) -> Optional[str]:
    if "piston-data" in url or "minecraft.net" in url:
        return None
    debug(f"Testing sidecar file at {url}.sha256")
    sidecar_url = f"{url}.sha256"
    try:
        req = urllib.request.Request(sidecar_url, headers=headers)
        with urllib.request.urlopen(req) as response:
            content = response.read().decode("utf-8").strip()

        hex_hash = content.split()[0]
        hash_bytes = bytes.fromhex(hex_hash)
        b64_string = base64.b64encode(hash_bytes).decode("utf-8")
        return format_sha(b64_string)

    except Exception:
        return None


def hash_fetched_file(url: str) -> Optional[str]:
    info(f"Hashing fetched file {url}")
    sha256 = hashlib.sha256()
    try:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req) as response:
            while chunk := response.read(16384):
                sha256.update(chunk)

        digest = sha256.digest()
        b64_string = base64.b64encode(digest).decode("utf-8")
        return format_sha(b64_string)

    except Exception as e:
        warning(f"Could not fetch hash for {url} ({e})")
        return format_sha("X" * 64)


def get_sha_from_url(url: str) -> str:
    url = upgrade_to_https(url)
    debug(f"Getting sha256 for {url}")
    sha = sha_cache.get(url)
    if sha is None:
        sha = try_sidecar_url(url)
        if sha is None:
            sha = hash_fetched_file(url)
        sha_cache[url] = sha
    else:
        debug(f"Using cached hash")
    return sha


def maven_to_url(maven_name: str, base_url: str = "https://maven.fabricmc.net/") -> str:
    parts = maven_name.split(":")
    if len(parts) != 3:
        error(f"Malformed maven name {maven_name}")
        return ""
    group, artifact, version = parts
    group_path = group.replace(".", "/")
    if not base_url.endswith("/"):
        base_url += "/"
    return (
        f"{base_url}{group_path}/{artifact}/{version}/{artifact}-{version}.jar".replace(
            " ", "%20"
        )
    )
