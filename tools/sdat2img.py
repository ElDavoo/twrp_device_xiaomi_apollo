#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Convert an Android block-based OTA image (<name>.transfer.list + <name>.new.dat)
into a raw partition image. Only full OTAs are supported ("new", "erase" and
"zero" commands), which is what LineageOS ships.

usage: sdat2img.py <transfer.list> <new.dat> <out.img>
"""
import sys

BLOCK = 4096


def ranges(spec):
    nums = [int(x) for x in spec.split(",")]
    if nums[0] != len(nums) - 1 or nums[0] % 2:
        raise ValueError(f"bad range set: {spec}")
    return list(zip(nums[1::2], nums[2::2]))


def main(transfer_list, new_dat, out_img):
    with open(transfer_list) as f:
        lines = [l.strip() for l in f if l.strip()]
    version = int(lines[0])
    cmds = lines[2:] if version == 1 else lines[4:]
    plan, end = [], 0
    for line in cmds:
        op, _, arg = line.partition(" ")
        if op not in ("new", "erase", "zero"):
            raise SystemExit(f"unsupported command (incremental OTA?): {op}")
        rs = ranges(arg)
        end = max([end] + [b for _, b in rs])
        if op == "new":
            plan.extend(rs)
    with open(new_dat, "rb") as src, open(out_img, "wb") as dst:
        dst.truncate(end * BLOCK)
        for a, b in plan:
            dst.seek(a * BLOCK)
            left = (b - a) * BLOCK
            while left:
                chunk = src.read(min(left, 1 << 24))
                if not chunk:
                    raise SystemExit("new.dat is shorter than the transfer list says")
                dst.write(chunk)
                left -= len(chunk)
    print(f"{out_img}: {end} blocks")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    main(*sys.argv[1:])
