#!/usr/bin/env python3
"""Fetch only the Android export templates out of the official Godot 4.7.2-stable
export_templates.tpz (a 1.2 GB zip) using HTTP range requests, so the whole archive
does not have to be downloaded.

Usage: fetch_templates.py <dest_dir> [--list]
Files written: android_debug.apk, android_release.apk, version.txt
"""
import struct
import sys
import urllib.request
import zlib

START_URL = ("https://downloads.godotengine.org/?version=4.7.2&flavor=stable"
             "&slug=export_templates.tpz&platform=templates")
WANTED = {"templates/android_debug.apk", "templates/android_release.apk", "templates/version.txt"}


UA = {"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) godot-template-fetcher/1.0"}


def resolve(url):
    req = urllib.request.Request(url, method="HEAD", headers=UA)
    with urllib.request.urlopen(req, timeout=45) as r:
        return r.geturl(), int(r.headers["Content-Length"])


def fetch_range(url, start, end, retries=6):
    last = None
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers=dict(UA, Range="bytes=%d-%d" % (start, end)))
            with urllib.request.urlopen(req, timeout=45) as r:
                data = r.read()
            if len(data) != end - start + 1:
                raise IOError("short range read (%d != %d)" % (len(data), end - start + 1))
            return data
        except Exception as exc:  # network hiccup: retry
            last = exc
            print("  retry %d after error: %s" % (attempt + 1, exc), flush=True)
    raise SystemExit("range download failed: %s" % last)


def central_directory(url, size):
    tail_len = min(size, 256 * 1024)
    tail = fetch_range(url, size - tail_len, size - 1)
    eocd_pos = tail.rfind(b"PK\x05\x06")
    if eocd_pos < 0:
        raise SystemExit("EOCD not found")
    eocd = tail[eocd_pos:eocd_pos + 22]
    _, _, _, _, cd_entries, cd_size, cd_offset, _ = struct.unpack("<IHHHHIIH", eocd)
    if cd_offset == 0xFFFFFFFF or cd_entries == 0xFFFF:
        loc_pos = tail.rfind(b"PK\x06\x07", 0, eocd_pos)
        if loc_pos < 0:
            raise SystemExit("ZIP64 locator not found")
        z64_eocd_offset = struct.unpack("<Q", tail[loc_pos + 8:loc_pos + 16])[0]
        z64 = fetch_range(url, z64_eocd_offset, z64_eocd_offset + 55)
        cd_entries = struct.unpack("<Q", z64[32:40])[0]
        cd_size = struct.unpack("<Q", z64[40:48])[0]
        cd_offset = struct.unpack("<Q", z64[48:56])[0]
    cd = fetch_range(url, cd_offset, cd_offset + cd_size - 1)
    entries = []
    pos = 0
    while pos + 46 <= len(cd) and cd[pos:pos + 4] == b"PK\x01\x02":
        (_, _, _, _, method, _, _, _, comp_size, uncomp_size, name_len, extra_len, comment_len,
         _, _, _, local_offset) = struct.unpack("<IHHHHHHIIIHHHHHII", cd[pos:pos + 46])
        name = cd[pos + 46:pos + 46 + name_len].decode("utf-8")
        extra = cd[pos + 46 + name_len:pos + 46 + name_len + extra_len]
        # ZIP64 extra field
        if comp_size == 0xFFFFFFFF or uncomp_size == 0xFFFFFFFF or local_offset == 0xFFFFFFFF:
            epos = 0
            while epos + 4 <= len(extra):
                hid, hlen = struct.unpack("<HH", extra[epos:epos + 4])
                if hid == 0x0001:
                    fields = extra[epos + 4:epos + 4 + hlen]
                    fpos = 0
                    if uncomp_size == 0xFFFFFFFF:
                        uncomp_size = struct.unpack("<Q", fields[fpos:fpos + 8])[0]
                        fpos += 8
                    if comp_size == 0xFFFFFFFF:
                        comp_size = struct.unpack("<Q", fields[fpos:fpos + 8])[0]
                        fpos += 8
                    if local_offset == 0xFFFFFFFF:
                        local_offset = struct.unpack("<Q", fields[fpos:fpos + 8])[0]
                    break
                epos += 4 + hlen
        entries.append((name, method, comp_size, uncomp_size, local_offset))
        pos += 46 + name_len + extra_len + comment_len
    return entries


def extract(url, entry, dest_path):
    name, method, comp_size, uncomp_size, local_offset = entry
    header = fetch_range(url, local_offset, local_offset + 29)
    assert header[:4] == b"PK\x03\x04", "bad local header for " + name
    name_len, extra_len = struct.unpack("<HH", header[26:30])
    data_start = local_offset + 30 + name_len + extra_len
    print("  downloading %s (%.1f MB)" % (name, comp_size / 1e6), flush=True)
    with open(dest_path, "wb") as out:
        chunk = 8 * 1024 * 1024
        decomp = zlib.decompressobj(-15) if method == 8 else None
        pos = data_start
        end = data_start + comp_size - 1
        written = 0
        while pos <= end:
            stop = min(pos + chunk - 1, end)
            data = fetch_range(url, pos, stop)
            if decomp:
                data = decomp.decompress(data)
            out.write(data)
            written += len(data)
            pos = stop + 1
        if decomp:
            tail = decomp.flush()
            out.write(tail)
            written += len(tail)
    assert written == uncomp_size, "size mismatch for %s: %d != %d" % (name, written, uncomp_size)
    print("  ok %s -> %s" % (name, dest_path), flush=True)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    dest = sys.argv[1]
    url, size = resolve(START_URL)
    print("archive: %s (%.1f MB)" % (url, size / 1e6), flush=True)
    entries = central_directory(url, size)
    if "--list" in sys.argv:
        for e in entries:
            print("%-45s method=%d comp=%d uncomp=%d" % (e[0], e[1], e[2], e[3]))
        return
    import os
    os.makedirs(dest, exist_ok=True)
    found = 0
    for e in entries:
        if e[0] in WANTED:
            target = os.path.join(dest, os.path.basename(e[0]))
            if os.path.exists(target) and os.path.getsize(target) == e[3]:
                print("  already complete:", target, flush=True)
            else:
                extract(url, e, target)
            found += 1
    if found != len(WANTED):
        raise SystemExit("only %d of %d wanted templates found" % (found, len(WANTED)))
    print("templates ready in", dest)


if __name__ == "__main__":
    main()
