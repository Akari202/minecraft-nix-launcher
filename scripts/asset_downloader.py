import argparse
import asyncio
import hashlib
import json
import logging
import os
from logging import debug, error, info, warning
from typing import Any, Dict

import aiohttp

BASE_URL: str = "https://resources.download.minecraft.net"
SEMAPHORE_LIMIT: int = 20


def verify_local_sha1(path: str, expected_sha: str) -> bool:
    if not os.path.exists(path):
        return False

    sha = hashlib.sha1()
    with open(path, "rb") as f:
        while chunk := f.read(65536):
            sha.update(chunk)

    return sha.hexdigest() == expected_sha


async def download_file(
    session: aiohttp.ClientSession,
    semaphore: asyncio.Semaphore,
    sha: str,
    path: str,
):
    url: str = f"{BASE_URL}/{sha[:2]}/{sha}"

    if os.path.exists(path):
        if verify_local_sha1(path, sha):
            return
        else:
            warning(f"Hash mismatch for existing file {sha}, redownloading")
            os.remove(path)

    async with semaphore:
        try:
            async with session.get(url) as response:
                if response.status == 200:
                    content: bytes = await response.read()

                    downloaded_sha: str = hashlib.sha1(content).hexdigest()
                    if downloaded_sha != sha:
                        error(
                            f"Network corruption, downloaded hash {downloaded_sha} did not match expected {sha}"
                        )
                        return

                    os.makedirs(os.path.dirname(path), exist_ok=True)
                    with open(path, "wb") as file:
                        file.write(content)

                else:
                    warning(f"Failed to download {sha}: HTTP {response.status}")
        except Exception as e:
            error(f"Error downloading {sha}: {e}")


async def main():
    parser = argparse.ArgumentParser(
        description="Download Minecraft assets from an index file"
    )
    parser.add_argument(
        "--index",
        required=True,
        help="Path to the asset index JSON file",
    )
    parser.add_argument(
        "--objects-dir",
        required=True,
        help="Target directory where assets will be saved",
    )

    args: argparse.Namespace = parser.parse_args()

    if not os.path.exists(args.index):
        error(f"Asset index file not found at {args.index}")
        return

    with open(args.index, "r") as file:
        data: Dict[str, Any] = json.load(file)

    objects: Dict[str, Dict[str, Any]] = data.get("objects", {})
    info(f"Found {len(objects)} assets to verify and download")

    semaphore: Dict[str, Dict[str, Any]] = asyncio.Semaphore(SEMAPHORE_LIMIT)
    async with aiohttp.ClientSession() as session:
        tasks: list[asyncio.Task[None]] = []
        for i, j in objects.items():
            sha: str = j["hash"]
            path: str = os.path.join(args.objects_dir, sha[:2], sha)
            task: asyncio.Task[None] = asyncio.create_task(
                download_file(session, semaphore, sha, path)
            )
            tasks.append(task)

        await asyncio.gather(*tasks)
    info("Asset download sync complete")


if __name__ == "__main__":
    logging.basicConfig(format="%(levelname)s: %(message)s", level=logging.INFO)
    asyncio.run(main())
