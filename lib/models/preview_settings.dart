enum PreviewBackground { off, screenshot, slideshow, video }

enum PreviewDownloadPolicy { manual, wifi, any }

/// Local preferences only. No provider URLs, account grants or game identities.
class PreviewSettings {
  final bool enabled, modelVisible, autoplay, loop, sound, normalized;
  final PreviewBackground background;
  final PreviewDownloadPolicy downloads;
  final double blur, brightness;
  final int cacheMiB;
  const PreviewSettings(
      {this.enabled = true,
      this.modelVisible = true,
      this.autoplay = true,
      this.loop = true,
      this.sound = true,
      this.normalized = false,
      this.background = PreviewBackground.video,
      this.downloads = PreviewDownloadPolicy.wifi,
      this.blur = 4,
      this.brightness = .45,
      this.cacheMiB = 512});

  Map<String, dynamic> toJson() => {
        'version': 1,
        'enabled': enabled,
        'modelVisible': modelVisible,
        'autoplay': autoplay,
        'loop': loop,
        'sound': sound,
        'normalized': normalized,
        'background': background.name,
        'downloads': downloads.name,
        'blur': blur,
        'brightness': brightness,
        'cacheMiB': cacheMiB
      };

  factory PreviewSettings.fromJson(Map<String, dynamic> json) {
    final defaults = const PreviewSettings();
    double number(String key, double fallback, double min, double max) =>
        json[key] is num && (json[key] as num).isFinite
            ? (json[key] as num).toDouble().clamp(min, max)
            : fallback;
    bool flag(String key, bool fallback) =>
        json[key] is bool ? json[key] as bool : fallback;
    return PreviewSettings(
        enabled: flag('enabled', true),
        modelVisible: flag('modelVisible', true),
        autoplay: flag('autoplay', true),
        loop: flag('loop', true),
        sound: flag('sound', true),
        normalized: flag('normalized', false),
        background: PreviewBackground.values
                .where((v) => v.name == json['background'])
                .firstOrNull ??
            defaults.background,
        downloads: PreviewDownloadPolicy.values
                .where((v) => v.name == json['downloads'])
                .firstOrNull ??
            defaults.downloads,
        blur: number('blur', 4, 0, 20),
        brightness: number('brightness', .45, 0, 1),
        cacheMiB: (json['cacheMiB'] is int ? json['cacheMiB'] as int : 512)
            .clamp(128, 2048));
  }

  PreviewSettings change(String key, Object value) =>
      PreviewSettings.fromJson({...toJson(), key: value});
}
