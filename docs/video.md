# Video

## The Vega decodes H.264 and HEVC, not VP9 or AV1

The Radeon Pro Vega's video decoder (UVD 7) is reachable through VA-API with
Mesa's `radeonsi` driver (`/usr/lib/dri/radeonsi_drv_video.so`). Tested with
`ffmpeg -hwaccel vaapi` on Mesa 26.2.5: H.264 and HEVC decode in hardware;
VP9 and AV1 fail with `No support for codec vp9 profile 0` (and `av1`), so
they always fall back to the CPU.

Chromium already uses the hardware decoder without any flags. In Chromium 155,
an H.264 file played with `VaapiVideoDecoder` (`kIsPlatformVideoDecoder =
true`) and the renderer at 0 % CPU. The features older guides name,
`AcceleratedVideoDecodeLinuxGL` and `AcceleratedVideoDecodeLinuxZeroCopyGL`,
no longer exist in this version.

## YouTube sent AV1, decoded on the CPU

YouTube prefers AV1, then VP9, so on this machine its videos ran in software
(`Dav1dVideoDecoder`, with a dozen `dav1d-worker` threads in the renderer).
`./install.sh video` installs a small Chromium extension of our own,
[`youtube-h264`](../config/home/.local/share/imac-pro-omarchy/chromium/youtube-h264/),
to `~/.local/share/imac-pro-omarchy/chromium/youtube-h264`. On YouTube pages,
including embedded players, it reports VP8, VP9 and AV1 as unsupported
(`MediaSource.isTypeSupported`, `canPlayType`, `mediaCapabilities`), so the
player picks H.264. Measured on 2026-10-26 with an embedded YouTube video
held at 1920×1080, 60 fps, in a fresh Chromium profile, over 10 s:

| | Video decoder | `dav1d` threads | GPU decoder (`drm-engine-dec`) | Chromium CPU, all processes |
|---|---|---|---|---|
| Without the extension | `Dav1dVideoDecoder` (AV1, software) | 15 | idle | 105 % of one thread |
| With the extension | `VaapiVideoDecoder` (H.264, hardware) | 0 | busy 82 % of the time | 28 % of one thread |

No frames were dropped in either run.

The cost: YouTube offers H.264 only up to 1080p, without HDR. Other sites keep
their usual codecs.

Omarchy loads its own extensions with one comma-separated `--load-extension`
switch in `~/.config/chromium-flags.conf`. A second switch would replace that
list, so the step appends the path to it, with a backup of the file next to
it. Restart Chromium afterwards. `./install.sh video-stock` takes it out again.

`omarchy-refresh-chromium` rewrites the flags file from Omarchy's defaults
and drops the path. `./check.sh` then warns, and `./install.sh video` puts it
back. It also warns while a Chromium that started before the step is still
running.

To see the decoder of a playing video, open DevTools → More tools → Media and
look at `kVideoDecoderName`.
