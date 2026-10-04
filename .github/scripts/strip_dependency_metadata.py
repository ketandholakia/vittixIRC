#!/usr/bin/env python3
"""Strip the 'Dependency metadata' APK Signing Block pair (ID 0x504b4453).

F-Droid's reproducibility scanner (froiddata CI, `fdroid scanner`) flags
reference APKs that carry extra signing blocks.  Release builds made by the
Android Gradle Plugin include a 'Dependency metadata' block; removing it keeps
the v2 signature fully valid (the signing block itself is not covered by the
v2 digests) and the APK verifiable.  The block is rebuilt in place:
[content][size][pairs'][size][magic][CD][EOCD], and the EOCD central-directory
offset is fixed up.

Usage: strip_dependency_metadata.py APK [APK ...]
Exits 0 even when there is nothing to strip (safe for CI).
"""
import struct
import sys

MAGIC = b"APK Sig Block 42"
EOCD_MAGIC = b"\x50\x4b\x05\x06"
META_BLOCK_ID = bytes.fromhex("53444b50")  # 0x504b4453 'Dependency metadata'


def strip(path: str) -> bool:
    with open(path, "rb") as fh:
        data = fh.read()
    mpos = data.rfind(MAGIC)
    if mpos < 0:
        print(f"{path}: no APK Signing Block, skipping")
        return False
    size2 = int.from_bytes(data[mpos - 8:mpos], "little")
    sb_offset = mpos - size2 + 8            # start of the first size field
    pairs_len = size2 - 24
    pairs = data[sb_offset + 8:sb_offset + 8 + pairs_len]
    offset = None
    i = 0
    while i + 12 <= len(pairs):
        ln = int.from_bytes(pairs[i:i + 8], "little")
        if ln == 0 or i + 8 + ln > len(pairs):
            break
        if pairs[i + 8:i + 12] == META_BLOCK_ID:
            offset = i
            break
        i += 8 + ln
    if offset is None:
        print(f"{path}: no 'Dependency metadata' block, skipping")
        return False
    ln = int.from_bytes(pairs[offset:offset + 8], "little")
    removed = 8 + ln
    new_pairs = pairs[:offset] + pairs[offset + removed:]
    new_size = len(new_pairs) + 24
    new_block = struct.pack("<Q", new_size) + new_pairs + struct.pack("<Q", new_size) + MAGIC
    out = data[:sb_offset] + new_block + data[sb_offset + 8 + size2:]
    eocd = out.rfind(EOCD_MAGIC)
    if eocd < 0:
        raise SystemExit(f"{path}: EOCD not found")
    old_cd = int.from_bytes(out[eocd + 16:eocd + 20], "little")
    new_cd = old_cd - removed
    out = out[:eocd + 16] + new_cd.to_bytes(4, "little") + out[eocd + 20:]
    with open(path, "wb") as fh:
        fh.write(out)
    print(f"{path}: removed {removed}-byte 'Dependency metadata' block")
    return True


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    for apk in sys.argv[1:]:
        strip(apk)
