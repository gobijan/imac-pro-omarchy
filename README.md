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
| Wi-Fi (BCM4364) | ✅ | Needs Apple's firmware, kept in a private repo, see [Wi-Fi firmware](#wi-fi-firmware) |
| Bluetooth | ✅ | |
| FaceTime HD camera, ambient light sensor | ✅ | Needs the T2 USB power rule (`./install.sh udev`) |
| Suspend (deep S3) | ✅ | Also with the 5K patch, see [docs/sleep.md](docs/sleep.md) |
| Hibernate | ❔ | Set up by Omarchy, never tested |
| Fan control | ✅ | Patched `t2fanrd`: idles at 800 instead of 1100 rpm, see [docs/fans.md](docs/fans.md) |

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

## Wi-Fi firmware

The Wi-Fi firmware is Apple's and may not be redistributed, so it isn't in
this repo. On the iMac Pro it can't be downloaded again without macOS either
([details](docs/wifi-bluetooth.md)). Once macOS is gone, your copy in
`/lib/firmware/brcm` is the only one. Put it into a **private** GitHub repo of
your own while it still works:

```bash
./backup-firmware.sh private-repo <your-user>/imac-pro-omarchy-firmware
```

`./install.sh firmware` restores it from there. By default it uses the
maintainer's private copy. Point it at yours with
`FIRMWARE_REPO=<your-user>/imac-pro-omarchy-firmware`. If you prefer offline
storage, `./backup-firmware.sh backup` writes an archive for a USB stick, and
`./backup-firmware.sh restore <archive>` puts it back.

## Setting up a fresh install

1. Install Omarchy. Wi-Fi stays down until the firmware is back, so use
   Ethernet or USB tethering.
2. Get this repo, including the pinned 5K patcher:

   ```bash
   git clone --recursive https://github.com/gobijan/imac-pro-omarchy ~/Work/imac-pro-omarchy
   cd ~/Work/imac-pro-omarchy
   ```

3. Run everything at once: firmware, audio, the T2 USB rule, the fan daemon and
   the 5K driver.
   The script installs the GitHub CLI and asks you to log in if needed, asks
   for your sudo password, and builds the 5K driver in 20 to 40 minutes.
   Reboot when it finishes.

   ```bash
   ./install.sh all     # or FIRMWARE_REPO=<your-user>/<repo> ./install.sh all
   ```

   Each step also runs on its own: `firmware`, `audio`, `udev`, `fans`, `display`,
   `5k`. `./install.sh fans-stock` returns to Omarchy's own fan daemon.

4. Check everything:

   ```bash
   ./check.sh
   ```

## After updates

The fans need nothing: the quiet fan daemon lives outside pacman's reach and
survives package and Omarchy updates ([docs/fans.md](docs/fans.md)).
`./check.sh` confirms it.

A new `linux-t2` comes with the stock GPU driver, so the panel drops back to
4K. Reboot into the new kernel, then rebuild:

```bash
./install.sh 5k
```

The 5K patch supports kernel 7.1.x and 7.2.x. On 7.3 or newer it refuses
cleanly until upstream has ported it, and you keep the stock 4K picture.

## Layout

```text
install.sh              firmware | audio | udev | fans | display | 5k | all; backs up every file it replaces
check.sh                read-only health check (display, audio, Wi-Fi, fans, sleep)
backup-firmware.sh      private-repo / backup / restore for Apple's Broadcom firmware
config/home/            files that go to ~ (Hyprland, PipeWire, UCM, systemd user drop-ins)
config/etc/             files that go to /etc (udev rule, fan daemon unit and config)
patches/                t2fanrd-quiet.patch: lower idle fan speed for t2fanrd
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
