#!/usr/bin/env bash
#
# install.sh — restore this repo's iMac Pro (iMacPro1,1) setup on Omarchy.
#
#   ./install.sh firmware    Apple Wi-Fi/Bluetooth firmware from a private GitHub repo (sudo)
#   ./install.sh audio       four-speaker crossover + UCM override (no sudo)
#   ./install.sh udev        keep the T2 USB hub awake: camera, light sensor, headset (sudo)
#   ./install.sh fans        patched t2fanrd: fans idle at 800 instead of 1100 rpm (sudo)
#   ./install.sh fans-stock  back to Omarchy's own t2fanrd and fan config (sudo)
#   ./install.sh sleep       detach Thunderbolt around sleep, so waking skips a ~60 s wait (sudo)
#   ./install.sh sleep-stock remove that sleep hook again (sudo)
#   ./install.sh gmux        mask the gmux GPE that floods CPU 0 after every wake, now and at boot (sudo)
#   ./install.sh gmux-stock  unmask it again (sudo)
#   ./install.sh video       Chromium extension: YouTube in H.264, decoded on the GPU (no sudo)
#   ./install.sh video-stock remove that extension again (no sudo)
#   ./install.sh power       balanced power profile instead of performance, kept across logins (no sudo)
#   ./install.sh power-stock let Omarchy pick performance again (no sudo)
#   ./install.sh display     Hyprland monitor rule: 5K at scale 2, 10 bpc, Display P3
#   ./install.sh 5k          build the patched amdgpu module (sudo, 20-40 min), then display
#   ./install.sh all         firmware + audio + udev + fans + sleep + gmux + video + power + 5k
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
T2FANRD_URL=https://github.com/GnomedDev/t2fanrd
T2FANRD_COMMIT=48baf962697ec3d4d969c74cf601ee8e15b7aeaa
FAN_BIN=/usr/local/bin/t2fanrd-quiet
TB_SLEEP_BIN=/usr/local/bin/imacpro-tb-sleep
TB_SLEEP_UNIT=/etc/systemd/system/imacpro-tb-sleep.service
GMUX_CMDLINE=/etc/limine-entry-tool.d/imacpro-gmux.conf
GMUX_GPE=/sys/firmware/acpi/interrupts/gpe13
CHROMIUM_FLAGS="$HOME/.config/chromium-flags.conf"
H264_EXT="$HOME/.local/share/imac-pro-omarchy/chromium/youtube-h264"
POWER_STATE="${OMARCHY_POWERPROFILES_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/powerprofiles}/ac"
STAMP="$(date +%Y%m%d-%H%M%S)"

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
usage() { sed -n '4,20p' "$0" | sed 's/^# \{0,1\}//'; }

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

# The build sits outside pacman's paths and has its own unit and config, so
# neither package updates nor Omarchy migrations undo it.
do_fans() {
    [[ -e /sys/bus/acpi/devices/APP0001:00/fan1_output ]] \
        || die "fans: no T2 fan controller (APP0001:00)"
    command -v cargo >/dev/null || sudo pacman -S --needed --noconfirm rust
    local tmp
    tmp="$(mktemp -d)"
    say "fans: building t2fanrd-quiet (t2fanrd ${T2FANRD_COMMIT:0:7} + patches/t2fanrd-quiet.patch)"
    git clone -q "$T2FANRD_URL" "$tmp/t2fanrd"
    git -C "$tmp/t2fanrd" checkout -q "$T2FANRD_COMMIT"
    git -C "$tmp/t2fanrd" apply "$REPO/patches/t2fanrd-quiet.patch"
    cargo build -q --release --locked --manifest-path "$tmp/t2fanrd/Cargo.toml"
    # Rename into place rather than overwrite the binary the daemon is running from.
    sudo install -Dm755 "$tmp/t2fanrd/target/release/t2fanrd" "$FAN_BIN.new"
    sudo mv -f "$FAN_BIN.new" "$FAN_BIN"
    rm -rf -- "$tmp"
    put_file "$CONFIG/etc/t2fand-quiet.conf" /etc/t2fand-quiet.conf sudo
    put_file "$CONFIG/etc/systemd/system/t2fanrd.service" /etc/systemd/system/t2fanrd.service sudo
    sudo systemctl daemon-reload
    # Omarchy enables the service; keep its enable link so fans-stock leaves nothing dangling.
    systemctl is-enabled -q t2fanrd.service || sudo systemctl enable t2fanrd.service
    sudo systemctl restart t2fanrd.service
    say "fans: t2fanrd-quiet running; at idle both fans settle near 800 rpm"
}

do_fans_stock() {
    [[ -e /usr/lib/systemd/system/t2fanrd.service ]] \
        || die "fans-stock: Omarchy's t2fanrd package is not installed, so there is nothing to go back to"
    sudo rm -f /etc/systemd/system/t2fanrd.service "$FAN_BIN" /etc/t2fand-quiet.conf
    sudo systemctl daemon-reload
    sudo systemctl reenable t2fanrd.service
    sudo systemctl restart t2fanrd.service
    say "fans-stock: Omarchy's t2fanrd running with /etc/t2fand.conf; the fans idle at 1100 rpm again"
}

# A unit of our own in /etc and a script in /usr/local: no package owns either.
do_sleep() {
    put_file "$CONFIG$TB_SLEEP_BIN" "$TB_SLEEP_BIN" sudo
    sudo chmod 755 "$TB_SLEEP_BIN"
    put_file "$CONFIG$TB_SLEEP_UNIT" "$TB_SLEEP_UNIT" sudo
    sudo systemctl daemon-reload
    sudo systemctl enable imacpro-tb-sleep.service
    say "sleep: Thunderbolt is detached before every sleep; waking no longer waits ~60 s for it"
}

do_sleep_stock() {
    sudo systemctl disable imacpro-tb-sleep.service 2>/dev/null || true
    sudo rm -f "$TB_SLEEP_UNIT" "$TB_SLEEP_BIN"
    sudo systemctl daemon-reload
    say "sleep-stock: hook removed; the first wake of each boot takes about 70 s again"
}

# Linux answers _OSI("Darwin") on Macs, so the gmux's GPE 13 only notifies
# apple-gmux, and after a wake from sleep it floods. Its interrupt only reports
# GPU power switches; the iMac Pro has one GPU, and the backlight needs none.
do_gmux() {
    command -v limine-update >/dev/null || die "gmux: limine-update is missing; this step expects Omarchy's Limine setup"
    put_file "$CONFIG$GMUX_CMDLINE" "$GMUX_CMDLINE" sudo
    sudo limine-update
    echo mask | sudo tee "$GMUX_GPE" >/dev/null
    say "gmux: GPE 13 masked now and, with acpi_mask_gpe=0x13, from every boot"
}

do_gmux_stock() {
    sudo rm -f "$GMUX_CMDLINE"
    command -v limine-update >/dev/null && sudo limine-update
    echo unmask | sudo tee "$GMUX_GPE" >/dev/null
    say "gmux-stock: GPE 13 unmasked; after a wake it floods CPU 0 again"
}

# Chromium's launcher splits each line into arguments; look at them with
# comments removed, as Omarchy's own omarchy-chromium-add-feature does.
chromium_args() { sed -E 's/(^|[[:space:]])#.*$//' "$CHROMIUM_FLAGS"; }

# Omarchy loads its extensions with one comma-separated --load-extension, and a
# second switch would replace that list, so the extension joins it.
do_video() {
    [[ -f $CHROMIUM_FLAGS ]] || die "video: $CHROMIUM_FLAGS is missing; is Omarchy's Chromium installed?"
    local f
    for f in manifest.json h264.js; do
        put_file "$CONFIG/home/.local/share/imac-pro-omarchy/chromium/youtube-h264/$f" "$H264_EXT/$f"
    done
    if chromium_args | grep -qF -- "$H264_EXT"; then
        say "unchanged: $CHROMIUM_FLAGS"
    else
        cp -a "$CHROMIUM_FLAGS" "$CHROMIUM_FLAGS.bak-$STAMP"
        say "backed up: $CHROMIUM_FLAGS.bak-$STAMP"
        if chromium_args | grep -qE -- '(^|[[:space:]])--load-extension='; then
            sed -i --follow-symlinks -E "s@^(([^#]*[[:space:]])?--load-extension=[^[:space:]#]*)@\1,$H264_EXT@" "$CHROMIUM_FLAGS"
        else
            [[ -z $(tail -c1 "$CHROMIUM_FLAGS") ]] || echo >>"$CHROMIUM_FLAGS"
            printf '%s\n' "--load-extension=$H264_EXT" >>"$CHROMIUM_FLAGS"
        fi
        say "installed: $H264_EXT in --load-extension of $CHROMIUM_FLAGS"
    fi
    say "video: restart Chromium; YouTube then plays H.264, decoded on the GPU"
}

do_video_stock() {
    if [[ -f $CHROMIUM_FLAGS ]] && grep -qF -- "$H264_EXT" "$CHROMIUM_FLAGS"; then
        local path=${H264_EXT//./\\.}
        cp -a "$CHROMIUM_FLAGS" "$CHROMIUM_FLAGS.bak-$STAMP"
        sed -i --follow-symlinks -E \
            -e "s@--load-extension=$path,@--load-extension=@" \
            -e "s@,$path@@g" \
            -e "\@^[[:space:]]*--load-extension=$path[[:space:]]*\$@d" "$CHROMIUM_FLAGS"
        say "video-stock: removed the extension from $CHROMIUM_FLAGS (backup: $CHROMIUM_FLAGS.bak-$STAMP)"
    fi
    rm -rf -- "$H264_EXT"
    say "video-stock: restart Chromium; YouTube picks AV1 or VP9 again, decoded on the CPU"
}

# At every login Omarchy runs omarchy-powerprofiles-set autodetect. On AC it
# restores the profile saved for ac, or picks performance when none is saved.
# Saving balanced is what picking it in Omarchy's power panel does.
do_power() {
    command -v omarchy-powerprofiles-set >/dev/null || die "power: omarchy-powerprofiles-set is missing; is this Omarchy?"
    omarchy-powerprofiles-set ac balanced
    say "power: balanced now and at every login (saved in $POWER_STATE)"
}

do_power_stock() {
    rm -f "$POWER_STATE"
    omarchy-powerprofiles-set autodetect
    say "power-stock: nothing saved for AC, so Omarchy picks performance, now and at every login"
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
        firmware|audio|udev|fans|display|5k) "do_$step" ;;
        fans-stock) do_fans_stock ;;
        sleep) do_sleep ;;
        sleep-stock) do_sleep_stock ;;
        gmux) do_gmux ;;
        gmux-stock) do_gmux_stock ;;
        video) do_video ;;
        video-stock) do_video_stock ;;
        power) do_power ;;
        power-stock) do_power_stock ;;
        all) do_firmware; do_audio; do_udev; do_fans; do_sleep; do_gmux; do_video; do_power; do_5k ;;
        -h|--help) usage ;;
        *) usage; exit 2 ;;
    esac
done
