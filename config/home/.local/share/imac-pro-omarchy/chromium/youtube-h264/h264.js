// Installed by imac-pro-omarchy (./install.sh video), see docs/video.md.
// The Radeon Pro Vega decodes H.264 in hardware but not VP9 or AV1. Telling
// YouTube's player that this browser can't play those makes it pick H.264.
(() => {
  const unwanted = /\b(av01|vp0?9|vp0?8)\b/i;
  const isUnwanted = (type) => typeof type === 'string' && unwanted.test(type);

  for (const MediaSourceType of [window.MediaSource, window.ManagedMediaSource]) {
    if (!MediaSourceType?.isTypeSupported) continue;
    const isTypeSupported = MediaSourceType.isTypeSupported.bind(MediaSourceType);
    MediaSourceType.isTypeSupported = (type) => !isUnwanted(type) && isTypeSupported(type);
  }

  const canPlayType = HTMLMediaElement.prototype.canPlayType;
  HTMLMediaElement.prototype.canPlayType = function (type) {
    return isUnwanted(type) ? '' : canPlayType.call(this, type);
  };

  const capabilities = navigator.mediaCapabilities;
  if (capabilities?.decodingInfo) {
    const decodingInfo = capabilities.decodingInfo.bind(capabilities);
    capabilities.decodingInfo = (config) => isUnwanted(config?.video?.contentType)
      ? Promise.resolve({ supported: false, smooth: false, powerEfficient: false })
      : decodingInfo(config);
  }
})();
