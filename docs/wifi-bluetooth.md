# Wi-Fi and Bluetooth

## Back up the firmware before you wipe the disk

The iMac Pro's Wi-Fi chip is a Broadcom BCM4364 (rev 3, Apple module name
"ekans"). Its firmware is Apple's, is not in `linux-firmware`, and cannot be
redistributed. On T2 Macs the usual sources are:

- **A macOS volume on the disk.** Omarchy's `apple-bcm-firmware-fetcher` reads
  the firmware from there during install. If you wiped macOS, the volume is gone.
- **A macOS Recovery image downloaded from Apple**, extracted with t2linux's
  `firmware.sh`. According to the
  [t2linux Wi-Fi guide](https://wiki.t2linux.org/guides/wifi-bluetooth/),
  this method **does not work on iMacPro1,1**.

So once macOS is gone, the files in `/lib/firmware/brcm` are your only copy.
Save them somewhere off the disk:

```bash
./backup-firmware.sh backup               # ~/apple-brcm-firmware-<date>.tar.zst (about 7 MB)
# copy that file to a USB stick or private storage. Never commit it.
```

After a fresh install:

```bash
./backup-firmware.sh restore /path/to/apple-brcm-firmware-<date>.tar.zst
```

The archive contains every Apple Broadcom file found in `/lib/firmware/brcm`.
The iMac Pro itself uses `brcmfmac4364b2-pcie.apple,ekans.*`.

## NVRAM symlink

On this machine the firmware first failed with:

```text
brcmf_pcie_download_fw_nvram: FW failed to initialize
```

This symlink fixed it:

```text
/lib/firmware/brcm/brcmfmac4364b2-pcie.apple,ekans.txt -> brcmfmac4364b2-pcie.apple,ekans-HRPN-u-7.5.txt
```

The backup archive keeps the symlink. If you get the firmware from somewhere
else, recreate it:

```bash
cd /lib/firmware/brcm
sudo ln -s 'brcmfmac4364b2-pcie.apple,ekans-HRPN-u-7.5.txt' 'brcmfmac4364b2-pcie.apple,ekans.txt'
```

## Already handled by Omarchy

- **WPA handshake:** Broadcom's firmware supplicant fails the WPA four-way
  handshake on Apple hardware, which shows up as a rejected password. Omarchy
  writes `/etc/modprobe.d/brcmfmac.conf` with `options brcmfmac feature_disable=0x82000`
  (its `fix-brcmfmac-supplicant.sh`).

## Harmless log noise

- `brcmf_p2p_set_firmware: failed to update device address ret -52` and the
  related `p2p-dev` errors only concern Wi-Fi Direct.
- Bluetooth (`BCM4364B0 Ekans Olympic`) logs `firmware Patch file not found ... 'brcm/BCM.hcd'`.
  It runs on its ROM firmware and works.

## Verify

```bash
journalctl -k -b 0 | grep 'Firmware: BCM4364'
bluetoothctl show | grep Powered
```
