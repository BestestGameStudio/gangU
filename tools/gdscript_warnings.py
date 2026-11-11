#!/usr/bin/env python3
"""List GDScript warnings for every script, as the editor reports them.

    python3 tools/gdscript_warnings.py --godot <godot binary> [--all] [--port N]

Runs the editor headless with its language server and opens each .gd file,
so the warnings are the ones the script editor shows for that file under the
project.godot warning settings. `--check-only` and headless runs print no
warnings, which is why this goes through the language server.

Prints one TSV row per warning (path, line, WARNING_NAME, message) to stdout
and per-category counts to stderr. By default only production scripts are
listed: tools/ and tests/ are skipped (--all keeps them).
"""
import argparse
import json
import os
import re
import socket
import subprocess
import sys
import time
from collections import Counter

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def is_harness(rel):
    return rel.startswith(("tools/", "tests/"))


class Lsp:
    def __init__(self, port):
        self.sock = None
        for _ in range(240):
            try:
                self.sock = socket.create_connection(("127.0.0.1", port))
                break
            except OSError:
                time.sleep(0.5)
        if self.sock is None:
            sys.exit("gdscript_warnings: the editor language server never came up")
        self.sock.settimeout(0.05)
        self.buf = b""
        self.next_id = 0
        self.diagnostics = {}

    def send(self, method, params, notify=False):
        msg = {"jsonrpc": "2.0", "method": method, "params": params}
        if not notify:
            self.next_id += 1
            msg["id"] = self.next_id
        body = json.dumps(msg).encode()
        self.sock.settimeout(None)
        self.sock.sendall(b"Content-Length: %d\r\n\r\n" % len(body) + body)
        self.sock.settimeout(0.05)

    def pump(self, seconds):
        end = time.time() + seconds
        while time.time() < end:
            try:
                chunk = self.sock.recv(1 << 20)
                if not chunk:
                    return
                self.buf += chunk
            except socket.timeout:
                pass
            while b"\r\n\r\n" in self.buf:
                head, rest = self.buf.split(b"\r\n\r\n", 1)
                length = int(re.search(rb"Content-Length:\s*(\d+)", head, re.I).group(1))
                if len(rest) < length:
                    break
                msg = json.loads(rest[:length])
                self.buf = rest[length:]
                if msg.get("method") == "textDocument/publishDiagnostics":
                    self.diagnostics[msg["params"]["uri"]] = msg["params"]["diagnostics"]

    def diagnose(self, path):
        uri = "file://" + path
        with open(path) as f:
            text = f.read()
        self.send("textDocument/didOpen", {"textDocument": {"uri": uri, "languageId": "gdscript", "version": 1, "text": text}}, notify=True)
        deadline = time.time() + 10
        while uri not in self.diagnostics and time.time() < deadline:
            self.pump(0.05)
        self.send("textDocument/didClose", {"textDocument": {"uri": uri}}, notify=True)
        return self.diagnostics.get(uri)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--godot", required=True)
    ap.add_argument("--all", action="store_true", help="include test harnesses and tools")
    ap.add_argument("--port", type=int, default=6151)
    args = ap.parse_args()

    files = []
    for d, dirs, names in os.walk(PROJECT):
        dirs[:] = sorted(x for x in dirs if not x.startswith("."))
        for n in names:
            if n.endswith(".gd"):
                rel = os.path.relpath(os.path.join(d, n), PROJECT)
                if args.all or not is_harness(rel):
                    files.append(rel)
    files.sort()

    editor = subprocess.Popen([args.godot, "--headless", "--editor", "--path", PROJECT, "--lsp-port", str(args.port)],
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        lsp = Lsp(args.port)
        lsp.send("initialize", {"processId": os.getpid(), "rootUri": "file://" + PROJECT, "rootPath": PROJECT, "capabilities": {}})
        lsp.pump(3)
        lsp.send("initialized", {}, notify=True)
        lsp.pump(3)
        counts = Counter()
        missing = []
        for rel in files:
            diags = lsp.diagnose(os.path.join(PROJECT, rel))
            if diags is None:
                missing.append(rel)
                continue
            for dg in diags:
                m = re.match(r"\((\w+)\):\s*(.*)", dg["message"], re.S)
                name = m.group(1) if m else ("ERROR" if dg.get("severity") == 1 else "UNKNOWN")
                msg = (m.group(2) if m else dg["message"]).replace("\n", " ")
                counts[name] += 1
                print("%s\t%d\t%s\t%s" % (rel, dg["range"]["start"]["line"] + 1, name, msg))
    finally:
        editor.kill()
    for name, n in sorted(counts.items(), key=lambda kv: -kv[1]):
        print("%6d %s" % (n, name), file=sys.stderr)
    print("%d scripts, %d warnings" % (len(files), sum(counts.values())), file=sys.stderr)
    if missing:
        sys.exit("gdscript_warnings: no diagnostics for %s" % ", ".join(missing))


if __name__ == "__main__":
    main()
