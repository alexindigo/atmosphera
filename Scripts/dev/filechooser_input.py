"""Command client for the private session's single Wayland keyboard owner."""

import os
import socket
import sys

from filechooser_isolation import checked


def main():
    checked()
    mode, *values = sys.argv[1:]
    if mode == "type":
        if values[:1] == ["--"]:
            values = values[1:]
        assert len(values) == 1
        line = "text " + " ".join(format(ord(char), "x") for char in values[0])
    elif mode == "key":
        for value in values:
            code, down = map(int, value.split(":"))
            assert 0 <= code <= 247 and down in (0, 1)
        line = "key " + " ".join(values)
    else:
        assert mode in ("ping", "stop") and not values
        line = mode
    with socket.socket(socket.AF_UNIX) as client:
        client.settimeout(10)
        client.connect(os.environ["FILECHOOSER_INPUT_SOCKET"])
        client.sendall((line + "\n").encode("ascii"))
        response = b""
        while not response.endswith(b"\n"):
            part = client.recv(1024)
            if not part:
                raise RuntimeError("private keyboard owner disconnected")
            response += part
        if response != b"OK\n":
            raise RuntimeError(response.decode())


if __name__ == "__main__":
    main()
