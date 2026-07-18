import atexit
import json
import os
import sys
from logging import debug, error, info, warning


class OutputFile:
    def __init__(self, filename: str):
        self.filename = filename

        self._file = open(self.filename, "w", encoding="utf-8")
        # self._file.write("{\n")
        # self.flush()

        atexit.register(self.close)

    def write_chunk(self, content: str):
        self._file.write(content)
        self.flush()

    def write(self, content: str):
        self._file.write(content)

    def flush(self):
        self._file.flush()
        os.fsync(self._file.fileno())

    def close(self):
        # self._file.write("}\n")
        # self.flush()
        self._file.close()
        self._file = None
        atexit.unregister(self.close)
