#!/usr/bin/env python3
"""Lenovo OSS tar からカーネルツリーだけを抜き出して tar.gz を作る（symlink 保持）"""
import sys
import tarfile

src_path, out_path = sys.argv[1], sys.argv[2]
prefix = "./kernel-4.14/msm-4.14"

entries = 0
total = 0
with tarfile.open(src_path, "r:") as src, tarfile.open(
    out_path, "w:gz", compresslevel=6
) as dst:
    for m in src:
        name = m.name
        if name != prefix and not name.startswith(prefix + "/"):
            continue
        if m.isfile():
            fobj = src.extractfile(m)
            dst.addfile(m, fobj)
            total += m.size
        else:
            dst.addfile(m, None)
        entries += 1

print(f"entries={entries} raw_bytes={total}")
