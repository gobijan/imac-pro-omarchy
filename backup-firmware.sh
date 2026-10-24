#!/usr/bin/env bash
#
# backup-firmware.sh — save or restore Apple's Broadcom Wi-Fi/Bluetooth firmware.
#
#   ./backup-firmware.sh backup [archive]   default: ~/apple-brcm-firmware-<date>.tar.zst
#   ./backup-firmware.sh restore <archive>  extracts into /lib/firmware/brcm (sudo)
#
# The files are Apple's and must not be published, so the archive never goes
# into this repo (see .gitignore). Keep it on a USB stick or private storage:
# on the iMac Pro they cannot be downloaded again without macOS.
set -euo pipefail

FW=/lib/firmware/brcm
say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

case ${1:-} in
backup)
    out=${2:-$HOME/apple-brcm-firmware-$(date +%Y%m%d).tar.zst}
    shopt -s nullglob
    files=("$FW"/*apple*)
    (( ${#files[@]} )) || die "no Apple firmware in $FW"
    files=("${files[@]#"$FW"/}")
    tar --zstd -cf "$out" -C "$FW" -- "${files[@]}"
    say "saved ${#files[@]} files to $out ($(du -h "$out" | cut -f1))"
    say "copy it off this disk before you wipe it, and never commit it"
    ;;
restore)
    [[ -f ${2:-} ]] || die "usage: $0 restore <archive>"
    sudo tar --zstd -xf "$2" -C "$FW" --no-same-owner
    sudo modprobe -r brcmfmac_wcc brcmfmac 2>/dev/null || true
    sudo modprobe brcmfmac
    say "restored; check with: journalctl -k -b 0 | grep 'Firmware: BCM4364'"
    ;;
*)
    sed -n '4,5p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac
