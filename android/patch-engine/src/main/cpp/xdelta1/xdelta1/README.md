# xdelta1 for Android

Sources of xdelta 1.x, its `libedsio` dependency and the glib subset it needs,
prepared for building with CMake/NDK from the UniPatcher app.

## Layout

    glib/        glib 2.26.0 subset (glib, gmodule, pcre, libcharset, gnulib)
                 + android/ (glibconfig.h) and android-internal/ (config.h)
    libedsio/    edsio serialization library
    xdelta1/     xdelta 1.x core

`glib/android/glibconfig.h` and `glib/android-internal/config.h` are preconfigured
for Android, so no autotools/configure run is needed. Everything not required to
compile (gio, gobject, gobject tests, po, docs, ChangeLogs, autotools/win32 build
files) was removed.

## Provenance

* `xdelta1/`, `libedsio/` — xdelta 1.x CVS snapshot by Josh MacDonald
  (`xdelta.c` rev 1.4.1.50.1.4, 2007), as vendored in
  <https://github.com/xperia64/android-rom-patcher> (the same copy UniPatcher
  used before this tree became a separate download). Originally
  <https://github.com/jmacd/xdelta>.
* `glib/` — glib 2.26.0, Android config headers from the same source.

## Local changes on top of upstream

* `xdelta1/nativelink.c` — new file, native glue for the JNI bridge.
* `glib/android/glibconfig.h` — `gsize`/`gssize`/`gintptr`, `GLIB_SIZEOF_*` and
  printf format modifiers now follow the target pointer size instead of being
  hardcoded to 32-bit (required for arm64-v8a/x86_64).

## Building

Targets are defined in the consumer project (`UniPatcher`'s
`app/src/main/cpp/xdelta1/CMakeLists.txt`), which builds `pcre`, `glib-2.0`,
`gmodule-2.0`, `edsio` and `xdelta1` as shared libraries and links them with
`log`/`dl`/`z`.

## Licenses

* `xdelta1/`, `libedsio/` — GPL-2.0-or-later (see `xdelta1/COPYING`,
  `libedsio/edsio.h`)
* `glib/`, `glib/glib/pcre/` — LGPL-2.1-or-later (see `glib/COPYING`)
