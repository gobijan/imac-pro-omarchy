#!/usr/bin/env bash
#
# backup-firmware.sh — save or restore Apple's Broadcom Wi-Fi/Bluetooth firmware.
#
#   ./backup-firmware.sh private-repo <owner>/<name>  push it to a new PRIVATE GitHub repo
#   ./backup-firmware.sh backup [archive]             default: ~/apple-brcm-firmware-<date>.tar.zst
#   ./backup-firmware.sh restore <archive>            extracts into /lib/firmware/brcm (sudo)
#
# The files are Apple's and must not be published, so they never go into this
# repo (see .gitignore). Keep them in a private repo, on a USB stick or in
# private storage: on the iMac Pro they cannot be downloaded again without macOS.
# `./install.sh firmware` restores from the private repo.
set -euo pipefail

FW=/lib/firmware/brcm
say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

collect() {   # fills files[] with the Apple firmware names in $FW
    shopt -s nullglob
    files=("$FW"/*apple*)
    (( ${#files[@]} )) || die "no Apple firmware in $FW"
    files=("${files[@]#"$FW"/}")
}

case ${1:-} in
private-repo)
    repo=${2:-}
    [[ $repo == ?*/?* ]] || die "usage: $0 private-repo <owner>/<name>"
    command -v gh >/dev/null && gh auth status >/dev/null 2>&1 \
        || die "needs the GitHub CLI, logged in: gh auth login"
    collect
    work="$(mktemp -d)"
    mkdir "$work/brcm"
    (cd "$FW" && cp -a --no-preserve=ownership -- "${files[@]}" "$work/brcm/")
    model="$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo unknown)"
    cat > "$work/README.md" <<EOF
# Apple Broadcom firmware (private)

${#files[@]} Wi-Fi/Bluetooth firmware files copied from \`$FW\` (model $model)
on $(date +%Y-%m-%d). They are Apple's and may not be redistributed, so
**keep this repository private**.

Restore with [imac-pro-omarchy](https://github.com/gobijan/imac-pro-omarchy):

\`\`\`bash
FIRMWARE_REPO=$repo ./install.sh firmware
\`\`\`
EOF
    git -C "$work" init -q -b main
    git -C "$work" add -A
    git -C "$work" commit -q -m "Apple Broadcom firmware from $model"
    gh repo create "$repo" --private --source="$work" --remote=origin --push \
        --description "Private: Apple Broadcom Wi-Fi/Bluetooth firmware (not redistributable)" >/dev/null
    rm -rf -- "$work"
    [[ $(gh repo view "$repo" --json visibility --jq .visibility) == PRIVATE ]] \
        || die "$repo is not private: make it private now (gh repo edit $repo --visibility private --accept-visibility-change-consequences)"
    say "pushed ${#files[@]} files to the private repo $repo"
    ;;
backup)
    out=${2:-$HOME/apple-brcm-firmware-$(date +%Y%m%d).tar.zst}
    collect
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
    sed -n '4,7p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac
