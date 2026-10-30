# Third-party material

## Speaker tuning

`config/home/.config/pipewire/imacpro-speakers.conf` uses the
filter coefficients from `config/90-imac-speakers.conf` in
[MrHogun/imac-a2115-linux](https://github.com/MrHogun/imac-a2115-linux). That
project read Apple's speaker tuning for the iMac19,1 out of macOS. Here the
channels are re-mapped for the iMac Pro, and both sides use the left-side
chains.

```text
MIT License

Copyright (c) 2026 MrHogun

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## 5K patcher

`vendor/imac5k-universal-linux-patcher` is a git submodule, not a copy. It
points at
[MarkPronkin/imac5k-universal-linux-patcher](https://github.com/MarkPronkin/imac5k-universal-linux-patcher)
at commit `37eef00`. Its scripts are MIT-licensed, and its kernel patches are
GPL-2.0. See that repository for details.

## t2fanrd

`./install.sh fans` builds
[GnomedDev/t2fanrd](https://github.com/GnomedDev/t2fanrd) at commit `48baf96`.
`patches/t2fanrd-quiet.patch` changes t2fanrd's code and is GPL-3.0-or-later,
like t2fanrd. `config/etc/systemd/system/t2fanrd.service` is based on the unit
in Omarchy's `t2fanrd` package.

## Hyprland monitor config

`config/home/.config/hypr/monitors.lua` is Omarchy's default `monitors.lua`
([omacom/omarchy](https://github.com/omacom/omarchy), MIT) with the iMac Pro
settings changed.

## Not included

Apple's Broadcom Wi-Fi/Bluetooth firmware. `backup-firmware.sh` puts your own
copy into a private GitHub repo or a private archive, and `.gitignore` keeps it
out of this repo.
