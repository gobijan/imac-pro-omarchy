#!/usr/bin/env bash
#
# install.sh — restore this repo's iMac Pro (iMacPro1,1) setup on Omarchy.
#
#   ./install.sh firmware  Apple Wi-Fi/Bluetooth firmware from a private GitHub repo (sudo)
#   ./install.sh audio     four-speaker crossover + UCM override (no sudo)
#   ./install.sh udev      keep the T2 USB hub awake: camera, light sensor, headset (sudo)
#   ./install.sh display   Hyprland monitor rule: 5K at scale 2, 10 bpc, Display P3
#   ./install.sh 5k        build the patched amdgpu module (sudo, 20-40 min), then display
#   ./install.sh all       firmware + audio + udev + 5k
#
# Every replaced file is backed up next to itself as <name>.bak-<timestamp>.
# Run it as your desktop user; it calls sudo only where it has to.
#
# The firmware is Apple's and may not be redistributed, so it lives in a private
# repo: FIRMWARE_REPO=<owner>/<name>, created with ./backup-firmware.sh private-repo.
set -euo pipefail

REPO="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
CONFIG="$REPO/config"
PATCHER="$REPO/vendor/imac5k-universal-linux-patcher/scripts/imac-patcher"
FIRMWARE_REPO="${FIRMWARE_REPO:-gobijan/imac-pro-omarchy-firmware}"
FW_DIR=/lib/firmware/brcm
UCM_SYSTEM=/usr/share/alsa/ucm2
UCM_USER="$HOME/.config/alsa-ucm2"
STAMP="$(date +%Y%m%d-%H%M%S)"

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
usage() { sed -n '4,10p' "$0" | sed 's/^# \{0,1\}//'; }

# put_file <source> <destination> [sudo]
put_file() {
    local src=$1 dst=$2 run=()
    [[ ${3:-} == sudo ]] && run=(sudo)
    if "${run[@]}" test -e "$dst"; then
        if "${run[@]}" cmp -s "$src" "$dst"; then
            say "unchanged: $dst"
            return
        fi
        "${run[@]}" cp -a "$dst" "$dst.bak-$STAMP"
        say "backed up: $dst.bak-$STAMP"
    fi
    "${run[@]}" install -Dm644 "$src" "$dst"
    say "installed: $dst"
}

# ALSA_CONFIG_UCM2 replaces the whole UCM tree, so mirror the packaged tree
# with symlinks and keep real files only for conf.d/AppleT2x4. Re-run after an
# alsa-ucm-conf update that adds new top-level entries.
mirror_ucm() {
    local entry name
    mkdir -p "$UCM_USER/conf.d"
    [[ -L $UCM_USER/conf.d/AppleT2x4 ]] && rm "$UCM_USER/conf.d/AppleT2x4"
    for entry in "$UCM_SYSTEM"/* "$UCM_SYSTEM"/conf.d/*; do
        name=${entry#"$UCM_SYSTEM"/}
        [[ $name == conf.d || $name == conf.d/AppleT2x4 ]] && continue
        if [[ -e $UCM_USER/$name && ! -L $UCM_USER/$name ]]; then
            warn "keeping $UCM_USER/$name (a real file, not a mirror link)"
            continue
        fi
        ln -sfn "$entry" "$UCM_USER/$name"
    done
    # Links whose target a package update removed.
    find "$UCM_USER" -maxdepth 2 -xtype l -delete
}

do_firmware() {
    if [[ -e "$FW_DIR/brcmfmac4364b2-pcie.apple,ekans.bin" && -e "$FW_DIR/brcmfmac4364b2-pcie.apple,ekans.txt" ]]; then
        say "firmware: iMac Pro Wi-Fi firmware already in place"
        return
    fi
    if ! command -v gh >/dev/null; then
        say "firmware: installing the GitHub CLI"
        sudo pacman -S --needed --noconfirm github-cli
    fi
    if ! gh auth status >/dev/null 2>&1; then
        say "firmware: log in to GitHub (Wi-Fi is down until this works: use Ethernet or USB tethering)"
        gh auth login
    fi
    local tmp
    tmp="$(mktemp -d)"
    say "firmware: fetching the private repo $FIRMWARE_REPO"
    gh repo clone "$FIRMWARE_REPO" "$tmp/fw" -- --depth 1 -q \
        || die "firmware: cannot clone $FIRMWARE_REPO. Set FIRMWARE_REPO=<owner>/<name> to your own private copy, or use ./backup-firmware.sh restore <archive>"
    [[ -d $tmp/fw/brcm ]] || die "firmware: $FIRMWARE_REPO has no brcm/ directory"
    sudo cp -a --no-preserve=ownership "$tmp/fw/brcm/." "$FW_DIR/"
    rm -rf -- "$tmp"
    sudo modprobe -r brcmfmac_wcc brcmfmac 2>/dev/null || true
    sudo modprobe brcmfmac
    say "firmware: installed; Wi-Fi should come up within a few seconds"
}

do_audio() {
    [[ -d $UCM_SYSTEM/conf.d/AppleT2x4 ]] \
        || die "apple-t2-audio-config is missing (Omarchy installs it on T2 Macs)"
    say "audio: mirroring $UCM_SYSTEM into $UCM_USER"
    mirror_ucm
    local f
    for f in AppleT2x4.conf HiFi.conf; do
        put_file "$CONFIG/home/.config/alsa-ucm2/conf.d/AppleT2x4/$f" "$UCM_USER/conf.d/AppleT2x4/$f"
    done
    for f in pipewire wireplumber; do
        put_file "$CONFIG/home/.config/systemd/user/$f.service.d/t2-ucm.conf" \
            "$HOME/.config/systemd/user/$f.service.d/t2-ucm.conf"
    done
    put_file "$CONFIG/home/.config/pipewire/pipewire.conf.d/imacpro-speakers.conf" \
        "$HOME/.config/pipewire/pipewire.conf.d/imacpro-speakers.conf"
    systemctl --user daemon-reload
    systemctl --user restart wireplumber pipewire pipewire-pulse
    say "audio: PipeWire restarted; the default output should be 'iMac Pro Speakers'"
}

do_udev() {
    put_file "$CONFIG/etc/udev/rules.d/90-t2-vhci-power.rules" /etc/udev/rules.d/90-t2-vhci-power.rules sudo
    sudo udevadm control --reload
    say "udev: takes effect at the next boot"
}

do_display() {
    put_file "$CONFIG/home/.config/hypr/monitors.lua" "$HOME/.config/hypr/monitors.lua"
    say "display: Hyprland reloads monitors.lua by itself"
    [[ -r /sys/module/amdgpu/parameters/tiled_stitch ]] \
        || warn "the stock amdgpu module is loaded: scale 2 on its 4K mode makes everything big until you run './install.sh 5k' and reboot"
}

do_5k() {
    [[ $(cat /sys/class/dmi/id/product_name 2>/dev/null) == iMacPro1,1 ]] \
        || die "this setup targets the iMac Pro (iMacPro1,1)"
    if [[ ! -x $PATCHER ]]; then
        say "5k: fetching the pinned upstream patcher (git submodule)"
        git -C "$REPO" submodule update --init
    fi
    "$PATCHER" --apply 5k
    do_display
    say "5k: reboot to load the patched module, then run ./check.sh"
}

(( $# )) || { usage; exit 2; }
[[ $EUID -ne 0 ]] || die "run as your desktop user; the script calls sudo itself"
for step in "$@"; do
    case $step in
        firmware|audio|udev|display|5k) "do_$step" ;;
        all) do_firmware; do_audio; do_udev; do_5k ;;
        -h|--help) usage ;;
        *) usage; exit 2 ;;
    esac
done
