#!/usr/bin/env bash
#
# check.sh — read-only health check for the iMac Pro setup. Changes nothing.
#
# Exit status: 0 when nothing failed, 1 otherwise.
set -uo pipefail

passed=0 failed=0 warned=0
ok()   { printf '\033[1;32m  ok\033[0m  %s\n' "$*"; passed=$((passed + 1)); }
bad()  { printf '\033[1;31mFAIL\033[0m  %s\n' "$*"; failed=$((failed + 1)); }
meh()  { printf '\033[1;33mwarn\033[0m  %s\n' "$*"; warned=$((warned + 1)); }
section() { printf '\n\033[1m%s\033[0m\n' "$*"; }

kernel_log="$(journalctl -k -b 0 --no-pager 2>/dev/null)"

section "System"
model="$(cat /sys/class/dmi/id/product_name 2>/dev/null)"
[[ $model == iMacPro1,1 ]] && ok "model $model" || meh "model is '${model:-unknown}', this repo targets iMacPro1,1"
krel="$(uname -r)"
pkgbase="$(cat "/usr/lib/modules/$krel/pkgbase" 2>/dev/null)"
[[ $pkgbase == linux-t2 ]] && ok "kernel package linux-t2" || bad "running '${pkgbase:-unknown}', not linux-t2 (keyboard, audio and sleep need it)"
case $krel in
    7.1.*|7.2.*) ok "kernel $krel is in the 5K patch's supported series (7.1, 7.2)" ;;
    *) bad "kernel $krel: the 5K patch supports only 7.1.x/7.2.x until it is re-ported upstream" ;;
esac

section "Display"
if [[ $(cat /sys/module/amdgpu/parameters/tiled_stitch 2>/dev/null) == 1 ]]; then
    ok "patched amdgpu loaded (tiled_stitch=1)"
else
    bad "stock amdgpu loaded: run ./install.sh 5k (normal right after a kernel update)"
fi
mode="$(head -n1 /sys/class/drm/card*-eDP-1/modes 2>/dev/null | head -n1)"
[[ $mode == 5120x2880 ]] && ok "panel mode $mode" || bad "panel mode ${mode:-unknown}, expected 5120x2880"
health="$(grep -E 'APPLE5K: link-health (PASS|FAIL)' <<<"$kernel_log" | tail -n1)"
case $health in
    *PASS*) ok "both tiles healthy at the last link check" ;;
    *FAIL*) bad "last link check failed: ${health##*APPLE5K: }" ;;
    *) meh "no link-health result in this boot's kernel log" ;;
esac
if monitors="$(hyprctl monitors -j 2>/dev/null)" && read -r scale format preset < <(python3 -I -c '
import json, sys
m = next(m for m in json.load(sys.stdin) if m["name"] == "eDP-1")
print(m["scale"], m["currentFormat"], m.get("colorManagementPreset", "unknown"))' <<<"$monitors" 2>/dev/null); then
    [[ $scale == 2 || $scale == 2.0* ]] && ok "Hyprland scale $scale (2560x1440 workspace)" || meh "Hyprland scale $scale, expected 2"
    [[ $format == XRGB2101010 ]] && ok "10-bit output ($format)" || meh "output format $format, expected XRGB2101010 (try: hyprctl reload)"
    [[ $preset == dp3 ]] && ok "colour preset dp3 (Display P3 panel)" || meh "colour preset $preset, expected dp3"
else
    meh "Hyprland not reachable or no eDP-1 output; skipped compositor checks"
fi

section "Audio"
sink="$(pactl get-default-sink 2>/dev/null)"
[[ $sink == imacpro_speakers ]] && ok "default output: iMac Pro Speakers (crossover)" || meh "default output is '${sink:-none}', expected imacpro_speakers (./install.sh audio)"
[[ $(systemctl --user show -p Environment pipewire 2>/dev/null) == *ALSA_CONFIG_UCM2* ]] \
    && ok "PipeWire uses the UCM override" || meh "PipeWire runs without ALSA_CONFIG_UCM2 (./install.sh audio)"

section "Video"
[[ -e /usr/lib/dri/radeonsi_drv_video.so ]] \
    && ok "VA-API driver for the Vega present (H.264 and HEVC in hardware, not VP9 or AV1)" \
    || bad "no /usr/lib/dri/radeonsi_drv_video.so: Chromium decodes all video on the CPU"
h264=$HOME/.local/share/imac-pro-omarchy/chromium/youtube-h264
if [[ -f $h264/h264.js ]] && sed -E 's/(^|[[:space:]])#.*$//' ~/.config/chromium-flags.conf 2>/dev/null | grep -qF -- "$h264"; then
    ok "YouTube H.264 extension in chromium-flags.conf"
    if pgrep -x chromium >/dev/null && ! pgrep -f -- "--load-extension=.*youtube-h264" >/dev/null; then
        meh "the running Chromium started before that: restart it to load the extension"
    fi
else
    meh "YouTube sends AV1 or VP9, decoded on the CPU (./install.sh video; again after omarchy-refresh-chromium)"
fi

section "Wi-Fi, Bluetooth, camera"
if grep -q 'brcmf_c_preinit_dcmds: Firmware: BCM4364' <<<"$kernel_log"; then
    ok "Wi-Fi firmware loaded"
else
    bad "Wi-Fi firmware did not load: see docs/wifi-bluetooth.md"
fi
compgen -G '/lib/firmware/brcm/brcmfmac4364b2-pcie.apple,ekans*' >/dev/null \
    && ok "iMac Pro Wi-Fi firmware files present (back them up: ./backup-firmware.sh backup)" \
    || bad "no brcmfmac4364b2-pcie.apple,ekans* files in /lib/firmware/brcm"
[[ $(bluetoothctl show 2>/dev/null) == *"Powered: yes"* ]] && ok "Bluetooth powered" || meh "Bluetooth not powered"
[[ -f /etc/udev/rules.d/90-t2-vhci-power.rules ]] && ok "T2 USB power rule installed" || meh "T2 USB power rule missing (./install.sh udev)"
compgen -G '/dev/video*' >/dev/null && ok "FaceTime camera present" || meh "no camera device"

section "Fans"
fans=/sys/bus/acpi/devices/APP0001:00
systemctl is-active -q t2fanrd && ok "t2fanrd running" || bad "t2fanrd not running: the SMC runs the fans on its own"
[[ $(systemctl show -p ExecStart --value t2fanrd 2>/dev/null) == *t2fanrd-quiet* && -x /usr/local/bin/t2fanrd-quiet ]] \
    && ok "t2fanrd-quiet in use (idle speed from /etc/t2fand-quiet.conf)" \
    || meh "stock t2fanrd: the fans idle at the SMC minimum of 1100 rpm (./install.sh fans)"
[[ $(cat "$fans/fan1_manual" 2>/dev/null) == 1 ]] \
    && ok "fans at $(cat "$fans/fan1_input") and $(cat "$fans/fan2_input") rpm, set by t2fanrd" \
    || meh "the SMC controls the fans (fan1_manual=0); t2fanrd-quiet takes over again within 30 s of a resume"

section "Power"
profile="$(powerprofilesctl get 2>/dev/null)"
case $profile in
    "") meh "power-profiles-daemon not reachable" ;;
    performance) meh "power profile performance: the CPU runs warmer and the fans faster (./install.sh power)" ;;
    *) ok "power profile $profile" ;;
esac
saved="$(cat "${OMARCHY_POWERPROFILES_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/powerprofiles}/ac" 2>/dev/null)"
[[ -n $saved && $saved != performance ]] \
    && ok "Omarchy restores $saved at every login" \
    || meh "Omarchy picks performance again at the next login (./install.sh power)"

section "Sleep"
[[ $(cat /sys/power/mem_sleep 2>/dev/null) == *"[deep]"* ]] && ok "suspend uses deep (S3)" || meh "suspend mode: $(cat /sys/power/mem_sleep 2>/dev/null)"
[[ $(systemctl is-enabled imacpro-tb-sleep.service 2>/dev/null) == enabled ]] \
    && ok "Thunderbolt is detached around sleep (imacpro-tb-sleep)" \
    || meh "no Thunderbolt sleep hook: the first wake of each boot waits ~60 s (./install.sh sleep)"
# Monotonic kernel timestamps stop during sleep, so this is the kernel's own resume time.
took="$(journalctl -k -b 0 --no-pager -o json --output-fields=_SOURCE_MONOTONIC_TIMESTAMP,MESSAGE \
    -g 'Low-level resume complete|PM: suspend exit' 2>/dev/null | python3 -I -c '
import json, sys
start = took = None
for line in sys.stdin:
    j = json.loads(line)
    t = int(j["_SOURCE_MONOTONIC_TIMESTAMP"]) / 1e6
    if "Low-level" in str(j.get("MESSAGE")):
        start = t
    elif start is not None:
        took, start = t - start, None
if took is not None:
    print(f"{took:.1f}")' 2>/dev/null)"
if [[ -z $took ]]; then
    meh "no wake from sleep in this boot yet"
elif (( ${took%.*} < 20 )); then
    ok "last wake took ${took} s in the kernel"
else
    bad "last wake took ${took} s in the kernel: it waited for Thunderbolt (docs/sleep.md)"
fi
gpes=/sys/firmware/acpi/interrupts
if read -r before _ < "$gpes/gpe_all" 2>/dev/null; then
    sleep 1
    read -r after _ < "$gpes/gpe_all"
    if (( after - before > 50 )); then
        top="$(grep -H . "$gpes"/gpe[0-9A-F][0-9A-F] | sort -t: -k2 -nr | head -n1)"
        top=${top%%:*}
        meh "ACPI interrupt storm: $((after - before))/s, mostly ${top##*/}; a kacpid kworker keeps one core busy and warms the fans"
    else
        ok "no ACPI interrupt storm ($((after - before))/s)"
    fi
fi

printf '\n%d ok, %d warnings, %d failed\n' "$passed" "$warned" "$failed"
(( failed == 0 ))
