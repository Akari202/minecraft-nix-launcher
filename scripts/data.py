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
