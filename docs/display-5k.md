# Native 5K display

## Why Linux shows 4K

The iMac Pro's 27" panel is 5120×2880, but it is built as two 2560×2880 tiles,
each fed by its own internal DisplayPort link (`eDP-1` for the left tile, `DP-1`
for the right). Apple's firmware leaves the panel in a single-link compatibility
mode, and the EDID it reports tops out at 3840×2160. With the stock `amdgpu`
driver you get one link, a 4K mode, and the panel's own scaler stretching it to
5K by a non-integer 1.33×. It looks sharp (about 163 ppi), but it is not native
(218 ppi).

## The fix

[MarkPronkin/imac5k-universal-linux-patcher](https://github.com/MarkPronkin/imac5k-universal-linux-patcher)
rebuilds the `amdgpu` module with patches that wake the second tile, stitch both
tiles into one 5120×2880 output and genlock them. Compositors such as Hyprland
then see a single ordinary 5K monitor. The iMac Pro (Vega, display engine
DCE 12) needs extra patches on top of the 2017 iMac stack, and the patcher ships them:

- The second tile is trained in DP rather than eDP panel mode. With eDP mode it
  trains but never locks video, and the panel shows the left tile stretched.
- DCE 12's timing generator gets the per-frame CRTC reset that genlocks the tiles.
- The stream must come up at the panel's native 10 bpc.

This repo pins the patcher as a git submodule at commit `37eef00`
(0.3.1-alpha, 2026-10-20), the version reviewed and verified on this machine.
The review found:

- The kernel patches only touch `drivers/gpu/drm/amd/` and add one module
  parameter, `amdgpu.tiled_stitch`.
- The build script downloads the matching kernel source from kernel.org,
  verifies its SHA-256, applies the patches with `--fuzz=0`, builds only the
  `amdgpu` module, checks that the module's vermagic matches the running kernel,
  and backs up the stock module before it replaces it. It refuses kernels
  outside the 7.1.x and 7.2.x series.

### What `./install.sh 5k` changes

1. It replaces `/usr/lib/modules/$(uname -r)/kernel/drivers/gpu/drm/amd/amdgpu/amdgpu.ko.zst`
   and keeps the original as `amdgpu.ko.zst.stock-backup`.
2. It writes `/etc/limine-entry-tool.d/imac5k-stitch.conf` with `amdgpu.tiled_stitch=1`.
3. It rebuilds the boot image with `limine-mkinitcpio`.
4. It installs `~/.config/hypr/monitors.lua` (see below).

The build needs `base-devel`, `bc`, `pahole` and the `linux-t2-headers` that
match the running kernel. The patcher offers to install anything missing. The
build takes 20 to 40 minutes and needs about 10 GB free.

### Hyprland rule

```lua
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale, bitdepth = 10, cm = "dp3" })
```

with `omarchy_monitor_scale = 2`:

- **Scale 2:** integer scaling gives a 2560×1440 workspace, the same as macOS.
  At 1.5, Hyprland silently rounds to 1.6.
- **`bitdepth = 10`:** the patcher requires it on the iMac Pro for the tiles to latch.
- **`cm = "dp3"`:** the panel is Display P3. Without this setting, Hyprland
  treats it as sRGB and everything looks oversaturated.

A second rule keeps `DP-1`, the panel's right tile, disabled (see
[Observed quirks](#observed-quirks)):

```lua
hl.monitor({ output = "DP-1", disabled = true })
```

Omarchy's scale buttons only change the two scale values at the top of
`monitors.lua`. They leave `bitdepth`, `cm` and the `DP-1` rule alone.

## Verify

```bash
./check.sh
journalctl -k -b 0 | grep 'APPLE5K: link-health'   # expect "PASS: both tiles healthy"
hyprctl monitors                                   # 5120x2880, scale 2, XRGB2101010, dp3
```

## After a kernel update

A new `linux-t2` comes with the stock `amdgpu`, so you are back to 4K. This is
expected. Reboot into the new kernel first, because the module is built for the
running kernel, then run:

```bash
./install.sh 5k
```

On kernel 7.3 or newer the patcher refuses until upstream has re-ported the
patches. Until then you get the stock 4K picture, nothing worse.

## Observed quirks

- **8-bit fallback:** On the first boot, Hyprland came up at 10 bit, then fell
  back to 8 bit (`XRGB8888`) after a DRM hotplug event from the second tile.
  A config reload (`hyprctl reload`) restored 10 bit.
- **Second display in Omarchy's panel:** Omarchy's display panel lists `DP-1`
  as a second, disabled display. It is the right half of the panel. The
  patched driver drives that link itself and marks the connector non-desktop,
  so Hyprland never uses it (`hyprctl monitors all` shows it as `disabled`,
  2560x2880, same description as `eDP-1`). Don't enable it: the panel's toggle
  would run `hl.monitor({ output = "DP-1", disabled = false, ... })` on the
  link the stitched output already uses. `monitors.lua` therefore pins it with
  `hl.monitor({ output = "DP-1", disabled = true })`. If it ever gets enabled,
  `hyprctl reload` turns it off again.
- **Standby:** Standby and wake work. The tiles re-lock within about three
  seconds of resume. See [sleep.md](sleep.md).

## Undo

```bash
vendor/imac5k-universal-linux-patcher/scripts/imac-patcher --remove 5k
```

Then set `omarchy_monitor_scale` back to `1.5` and remove `bitdepth = 10` from
the monitor rule.
