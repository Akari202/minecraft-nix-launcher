import atexit
import json
import os
from logging import debug, error, info, warning


class DiskDict(dict):
    def __init__(self, filename="cache.json"):
        self.filename = filename
        if os.path.exists(self.filename):
            try:
                with open(self.filename, "r") as f:
                    super().__init__(json.load(f))
                    debug(f"Using cached dict {filename}")
            except (json.JSONDecodeError, IOError):
                warning(f"Unable to decode {filename}, defauting to empty")
                super().__init__()
        else:
            super().__init__()

        atexit.register(self.save)

    def save(self):
        with open(self.filename, "w") as f:
            json.dump(self, f, indent=4)
