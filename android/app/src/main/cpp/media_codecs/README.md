# Local APK import codecs

These independently licensed codecs decode resources supplied by the user. No
Socket library, key, geometry, image or script is bundled here.

- `etc.cpp`, `etc.h`, `color.h`, `endianness.h`: unmodified Texture2DDecoder sources, commit
  `3ebc3b758bd6b1a3108b50148f7998ee34f058c6` from
  https://github.com/K0lb3/texture2ddecoder, MIT. See `Texture2DDecoder-LICENSE`.
- `FastNoiseLite.h`: unmodified header from Godot 4.5, commit
  `746e1ff4570b7c77e4d2b17254c924ef01092af2`,
  `thirdparty/misc/FastNoiseLite.h`. It retains its complete embedded MIT licence.
  Used only to reconstruct the source's procedural material from numeric settings.

The JNI boundary validates dimensions and exact block lengths before decoding.
Decoding is sequential on the import worker, not on Flutter's frame thread.
