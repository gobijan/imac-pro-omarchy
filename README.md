# iMac Pro (2017) on Omarchy

Configs, scripts and notes for running [Omarchy](https://omarchy.org) (Arch
Linux + Hyprland) on the **iMac Pro** (`iMacPro1,1`). They cover native 5K, all
four speakers with a proper crossover, a Wi-Fi firmware backup and working sleep.

Apple's new macOS releases no longer support Intel Macs. The hardware is still
good: an 8- to 18-core Xeon W, a Radeon Pro Vega and a 27" 5K Display P3 panel.
On Linux it runs well. Out of the box the panel runs at 4K upscaled, and the
speakers play without a crossover. This repo fixes both and documents the rest,
so a reinstall takes minutes instead of a day of research.

## Status

| Feature | Status | Notes |
|---|---|---|
| Native 5K: 5120×2880 at 60 Hz, 10 bit, Display P3 | ✅ | Patched `amdgpu` module, see [docs/display-5k.md](docs/display-5k.md) |
| Speakers: 2 woofers + 2 tweeters | ✅ | Crossover and Apple's EQ in PipeWire, see [docs/audio.md](docs/audio.md) |
| Headphone jack | ✅ | No jack detection; select the output by hand |
| Wi-Fi (BCM4364) | ✅ | Needs Apple firmware. **Back it up**, see [docs/wifi-bluetooth.md](docs/wifi-bluetooth.md) |
| Bluetooth | ✅ | |
| FaceTime HD camera, ambient light sensor | ✅ | Needs the T2 USB power rule (`./install.sh udev`) |
| Suspend (deep S3) | ✅ | Also with the 5K patch, see [docs/sleep.md](docs/sleep.md) |
| Hibernate | ❔ | Set up by Omarchy, never tested |
| Fan control | ✅ | Omarchy's `t2fanrd` |

Tested in October 2026 on an iMac Pro with a Radeon Pro Vega 64 and 32 GB RAM,
running Omarchy with Limine and Hyprland 0.56.2, `linux-t2` 7.2.11 and
Mesa 26.2.5.

## What Omarchy already does

When the installer finds a T2 chip it runs `install/hardware/apple/fix-t2.sh`,
which:

- installs `linux-t2` with its headers, `apple-t2-audio-config`,
  `apple-bcm-firmware-fetcher` and `t2fanrd`, and enables fan control
- loads the T2 keyboard modules from the initramfs
- boots with `intel_iommu=on iommu=pt pm_async=off mem_sleep_default=deep`

Two other Omarchy scripts add the `brcmfmac` WPA-handshake fix and the
Apple F-key mode. This repo covers only what comes on top of all that.

## Before you wipe the disk

**Back up the Wi-Fi firmware.** It is Apple's, so it can't live in this repo,
and on the iMac Pro it can't be downloaded again without macOS
([details](docs/wifi-bluetooth.md)).

```bash
./backup-firmware.sh backup      # writes ~/apple-brcm-firmware-<date>.tar.zst
```

Copy the archive to a USB stick or private storage.

## Setting up a fresh install

1. Install Omarchy. If Wi-Fi doesn't come up, use Ethernet or USB tethering.
2. Get this repo, including the pinned 5K patcher:

   ```bash
   git clone --recursive https://github.com/gobijan/imac-pro-omarchy ~/Work/imac-pro-omarchy
   cd ~/Work/imac-pro-omarchy
   ```

3. Restore the Wi-Fi firmware:

   ```bash
   ./backup-firmware.sh restore /path/to/apple-brcm-firmware-<date>.tar.zst
   ```

4. Install the audio setup and the T2 USB rule:

   ```bash
   ./install.sh audio udev
   ```

5. Build the 5K driver. This takes 20 to 40 minutes and asks for your sudo
   password. Reboot when it finishes.

   ```bash
   ./install.sh 5k
   ```

6. Check everything:

   ```bash
   ./check.sh
   ```

## After every kernel update

A new `linux-t2` comes with the stock GPU driver, so the panel drops back to
4K. Reboot into the new kernel, then rebuild:

```bash
./install.sh 5k
```

The 5K patch supports kernel 7.1.x and 7.2.x. On 7.3 or newer it refuses
cleanly until upstream has ported it, and you keep the stock 4K picture.

## Layout

```text
install.sh              audio | udev | display | 5k | all; backs up every file it replaces
check.sh                read-only health check (display, audio, Wi-Fi, sleep)
backup-firmware.sh      backup / restore Apple's Broadcom firmware
config/home/            files that go to ~ (Hyprland, PipeWire, UCM, systemd user drop-ins)
config/etc/             files that go to /etc (udev rule)
docs/                   the why and the how, one file per topic
vendor/                 imac5k-universal-linux-patcher, pinned at the reviewed commit
```

## Credits

- [MarkPronkin/imac5k-universal-linux-patcher](https://github.com/MarkPronkin/imac5k-universal-linux-patcher)
  It brings together the native-5K work from the
  [drm/amd#4455](https://gitlab.freedesktop.org/drm/amd/-/issues/4455)
  community: the tile wake and stitch patches, the genlock fix and nicktau's
  iMac Pro patches. It is based on ahmadtv's `omarchy-imac18-3-patch`.
- [MrHogun/imac-a2115-linux](https://github.com/MrHogun/imac-a2115-linux) for
  Apple's speaker tuning, read out of macOS.
- [t2linux](https://wiki.t2linux.org) for the T2 kernel, drivers and docs.
- [Omarchy](https://omarchy.org) for making T2 Macs work out of the box.

## Disclaimer

The 5K step replaces a GPU kernel module with an alpha-stage patched build. It
works on this machine, but there is no warranty. The stock module is backed up,
and `vendor/imac5k-universal-linux-patcher/scripts/imac-patcher --remove 5k`
restores it.

## License

MIT for this repo's own files. See [LICENSE](LICENSE) and
[THIRD_PARTY.md](THIRD_PARTY.md).
