#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Extract the recovery's vendor blobs from a LineageOS apollon OTA zip instead
# of a phone (used by CI). Needs: unzip, brotli, python3, fsck.erofs (erofs-utils).
#
# usage: tools/blobs_from_ota.sh <lineage-*-apollon-signed.zip> [workdir]

set -euo pipefail

ZIP="$(realpath "$1")"
TOOLS="$(cd "$(dirname "$0")" && pwd)"
WORK="${2:-$(mktemp -d)}"
mkdir -p "$WORK"
cd "$WORK"

unzip -o -q "$ZIP" vendor.new.dat.br vendor.transfer.list
brotli -d -f -o vendor.new.dat vendor.new.dat.br
rm vendor.new.dat.br
python3 -I "$TOOLS/sdat2img.py" vendor.transfer.list vendor.new.dat vendor.img
rm vendor.new.dat
rm -rf vendor
fsck.erofs --extract=vendor vendor.img >/dev/null
rm vendor.img

"$TOOLS/extract_blobs.sh" --from-dir "$WORK/vendor"
