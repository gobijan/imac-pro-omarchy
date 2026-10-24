# Audio: four speakers with a crossover

## Hardware

With linux-t2's `t2bce_audio` driver, the T2 exposes one card,
`Apple T2 Audio`, with these PCMs:

| PCM | What | Channels |
|---|---|---|
| 0 | speakers: 0 = left woofer, 1 = right woofer, 2 = left tweeter, 3 = right tweeter | 4 out |
| 1 | microphone array | 4 in |
| 100 | headphone jack codec | 2 out / 1 in |

The hardware has no crossover. Every driver gets exactly what you send it, so
sending full-range stereo to all four (a plain upmix) puts bass into the
tweeters.

## What this setup does

1. **UCM override** (`config/home/.config/alsa-ucm2/conf.d/AppleT2x4/`) replaces
   the packaged `AppleT2x4` profile from `apple-t2-audio-config` with one that
   exposes PCM 0 as a raw four-channel sink, *Speaker drivers (raw, no
   crossover)*, plus the mic array and the jack. PipeWire and WirePlumber pick
   it up through `ALSA_CONFIG_UCM2`, set by the two systemd user drop-ins
   (`t2-ucm.conf`).

   `ALSA_CONFIG_UCM2` replaces the whole UCM tree, so `~/.config/alsa-ucm2` is a
   mirror of `/usr/share/alsa/ucm2` built from symlinks. Only `conf.d/AppleT2x4`
   holds real files. `./install.sh audio` builds the mirror and also removes
   links that went stale. Re-run it after an `alsa-ucm-conf` update.

2. **PipeWire filter chain**
   (`config/home/.config/pipewire/pipewire.conf.d/imacpro-speakers.conf`) creates
   the stereo sink *iMac Pro Speakers*, `imacpro_speakers`, which becomes the
   default:

   ```text
   stereo in
     -> input EQ, 12 sections per channel
     -> pre-split gain -5 dB
     -> split: tweeters -> RL/RR, -2.5 dB, 2 high-passes near 3.0 kHz, EQ
               woofers  -> FL/FR, 3 low-passes near 1.39 kHz, EQ
   ```

   The coefficients are Apple's own speaker tuning for the iMac 27" 2019
   (iMac19,1), read out of macOS by
   [MrHogun/imac-a2115-linux](https://github.com/MrHogun/imac-a2115-linux) (MIT).
   The iMac Pro uses the same enclosure and four-driver layout. That it also
   uses the same drivers is an assumption, not confirmed. The channel order
   differs: on the iMac19,1 the tweeters are FL/FR, here the woofers are.
   Apple's level-dependent stages (compressor, limiter) are not reproduced.

   To trim the tweeters live, for example 1 dB below Apple's value:

   ```bash
   pw-cli s imacpro_speakers Props '{ params = [ "gtwl:Mult" 0.6657 "gtwr:Mult" 0.6657 ] }'
   ```

## Headphones

The jack has no detection. Pick *Apple Audio Device Headphones* by hand when
something is plugged in.

## Not used: `imac-patcher --apply t2speakers`

The upstream patcher's `t2speakers` module maps stereo to the four channels
with a simple upmix and no crossover. It also targets the `pro-output` profile,
which this setup does not use. Don't apply it on top of this setup.

## Install

```bash
./install.sh audio
```
