# Physical-media fallback artwork

S5-FORMAT-FALLBACK / UI-01 uses the colored Systematic `-content.png` family
from [libretro/retroarch-assets](https://github.com/libretro/retroarch-assets/tree/b177f250e42948708e753d30809bd4dd9c0a2cdc/xmb/systematic/png),
pinned to commit `b177f250e42948708e753d30809bd4dd9c0a2cdc`.

Systematic and RetroActive theme contributors provide this flat, outlined media
artwork. Upstream [Systematic guidelines](https://github.com/libretro/retroarch-assets/blob/b177f250e42948708e753d30809bd4dd9c0a2cdc/Systematic/README.md)
describe the shared RetroActive media, 256px layout and contrast border.
[RetroActive's source/credit reference](https://github.com/libretro/retroarch-assets/blob/b177f250e42948708e753d30809bd4dd9c0a2cdc/xmb/retroactive/README.md)
points to [baxysquare/baxy-retroarch-themes](https://github.com/baxysquare/baxy-retroarch-themes).
The root upstream COPYING applies CC BY 4.0; its complete unchanged text and
disclaimer are bundled here. NOTICE.md retains source, credits, license link,
no-endorsement notice and the filename-only modification declaration.
The normal About -> Licenses page exposes the bundled notice and license offline.

Only required PNG content icons are bundled. No theme fonts, UI, backgrounds,
console icons or controller icons are imported. Original PNG image bytes are
unchanged; filenames use canonical R-Shop platform IDs. `systematic/SOURCES.json`
records every original source path and Git blob SHA-1. Download-time and bundle
tests check exact blob identity, 256x256 dimensions, alpha and nonempty pixels.
No image editing, SVG/Canvas drawing or image generation was used for this set.
It replaces the previous generated app asset copies; the image tool's original
outputs are not altered or removed by this replacement.

`lib/widgets/media_cover_fallback.dart` supplies an explicit mapping for all
currently supported systems. Known console media use their corresponding content
icons, including the distinct N64 cartridge, Nintendo handheld cards, PSP UMD
and Famicom Disk System disk. Mixed-media computers without release-format evidence,
unknown platforms, arcade/integrated handheld and fantasy-console entries use the
same neutral `default-content.png` rocket. This is a game-content symbol, not a
controller or a fabricated physical-format claim. Archive/container suffixes and
provider names never select media. A future exact legacy-format mapping must be
supported by release evidence; S9 owns the final cartridge/legacy-format audit.

Runtime decoding remains bounded to 256px/shared image keys. Loading, missing,
failed and offline covers render the bundled image immediately, without initiating
requests. A valid decoded cover replaces it. Ratings, titles, focus and status
badges remain separate UI layers and are not baked into image files.
