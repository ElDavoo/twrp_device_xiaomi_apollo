#!/usr/bin/env python3
"""Copy a LineageOS OTA zip without the step that flashes recovery.img.

Every other entry is copied byte-for-byte with its original compression; the
updater-script loses only the two lines that print and write recovery.img.
The result is unsigned (TWRP installs it with zip verification off).
"""
import sys, zipfile, shutil

src, dst = sys.argv[1], sys.argv[2]
SCRIPT = "META-INF/com/google/android/updater-script"
DROP_LINES = {
    'ui_print("Patching recovery image...");',
    'package_extract_file("recovery.img", "/dev/block/bootdevice/by-name/recovery");',
}

with zipfile.ZipFile(src) as zin:
    bad = zin.testzip()
    if bad:
        sys.exit(f"CRC error in source entry {bad}")
    with zipfile.ZipFile(dst, "w", allowZip64=True) as zout:
        for info in zin.infolist():
            if info.filename == "recovery.img":
                print("dropped entry recovery.img")
                continue
            if info.filename == SCRIPT:
                text = zin.read(info).decode()
                kept = [l for l in text.split("\n") if l.strip() not in DROP_LINES]
                removed = len(text.split("\n")) - len(kept)
                if removed != 2:
                    sys.exit(f"expected to drop 2 updater-script lines, dropped {removed}")
                zout.writestr(info, "\n".join(kept).encode())
                print("patched updater-script (-2 lines)")
                continue
            with zin.open(info) as fi, zout.open(info, "w", force_zip64=info.file_size > 0x7fffffff) as fo:
                shutil.copyfileobj(fi, fo, 1 << 20)
with zipfile.ZipFile(dst) as z:
    bad = z.testzip()
    if bad:
        sys.exit(f"CRC error in output entry {bad}")
    print(f"ok: {len(z.infolist())} entries, recovery refs in script: "
          f"{z.read(SCRIPT).decode().count('recovery')}")
