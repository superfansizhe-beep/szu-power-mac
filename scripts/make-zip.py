#!/usr/bin/env python3
"""把 .app 打成 zip。

不能用 ditto 的默认参数：它不置 UTF-8 文件名标志，Linux / Python 解压会乱码。
这里用 zipfile 显式写入，文件名带 UTF-8 标志，同时保留可执行权限。

    python3 scripts/make-zip.py "深大电量.app" out.zip
"""
import os
import stat
import sys
import zipfile


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    app = sys.argv[1]
    out = sys.argv[2]
    if not os.path.isdir(app):
        print(f"不是目录：{app}")
        sys.exit(1)

    base = os.path.dirname(os.path.abspath(app))
    count = 0
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
        for root, _dirs, files in os.walk(app):
            for name in sorted(files):
                full = os.path.join(root, name)
                rel = os.path.relpath(full, base)
                info = zipfile.ZipInfo(rel)
                mode = os.stat(full).st_mode
                info.external_attr = (mode & 0xFFFF) << 16
                info.compress_type = zipfile.ZIP_DEFLATED
                with open(full, "rb") as fh:
                    zf.writestr(info, fh.read())
                count += 1
    print(f"已打包 {count} 个文件 -> {out}")


if __name__ == "__main__":
    main()
