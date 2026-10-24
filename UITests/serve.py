"""Synthetic RSS and its original page, bound only to IPv4 loopback."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import struct
import sys
import time
import zlib


def magenta_png(size=32):
    """A solid magenta PNG: the icon the home page names, easy to find in a screenshot."""
    raw = b"".join(b"\x00" + b"\xff\x00\xff" * size for _ in range(size))
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    header = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")


class Handler(BaseHTTPRequestHandler):
    # The icon feed's home page answers late, as a slow site does: after the refresh has returned (#441).
    home_delay = 4.0

    def do_GET(self):
        base = f"http://127.0.0.1:{self.server.server_port}"
        if self.path == "/checker.png":
            self.reply("image/png", magenta_png())
            return
        if self.path == "/feed.xml":
            content_type = "application/rss+xml"
            text = f"""<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel><title>Smoke local feed</title><link>{base}/article</link>
<description>A synthetic local feed</description>
<item><guid>smoke-one</guid><title>Smoke local article</title><link>{base}/article</link>
<description>Smoke local article body.</description></item></channel></rss>"""
        elif self.path == "/icon-feed.xml":
            content_type = "application/rss+xml"
            text = f"""<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel><title>Smoke icon feed</title><link>{base}/home</link>
<description>A synthetic feed that names no icon</description>
<item><guid>smoke-icon</guid><title>Smoke icon article</title><link>{base}/article</link>
<description>Smoke icon article body.</description></item></channel></rss>"""
        elif self.path == "/home":
            time.sleep(self.home_delay)
            content_type = "text/html"
            text = "<!doctype html><html lang='en'><head><title>Smoke home</title><link rel='icon' href='/checker.png' sizes='32x32'></head><body>Home</body></html>"
        elif self.path == "/article":
            content_type = "text/html"
            text = "<!doctype html><html lang='en'><title>Smoke original page</title><body><h1>Smoke original page</h1><p>A synthetic loopback page.</p></body></html>"
        else:
            self.send_error(404)
            return
        self.reply(content_type + "; charset=utf-8", text.encode("utf-8"))

    def reply(self, content_type, data):
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    Path(sys.argv[1]).write_text(f"http://127.0.0.1:{server.server_port}/feed.xml")
    server.serve_forever()
