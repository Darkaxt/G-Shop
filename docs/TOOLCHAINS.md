# Maintained Android release toolchain

G-Shop's local release entrypoint is `scripts/build_release.ps1`. It selects
Flutter 3.47.8 at `D:/Tools/flutter-3.47.8` and Microsoft JDK 25.0.4.1+1 at
`D:/Tools/jdk25-microsoft/jdk-25.0.4.1+1`, scoped to the build process. Override
the explicit `FlutterRoot` and `JavaHome` parameters for another installation.
The Android `local.properties` SDK binding must select that same Flutter SDK;
Flutter's configuration-only preparation updates it before the gated build.
Do not infer this project's compiler from a different `flutter` on global PATH.

The wrapper pins Gradle 9.8.2 and its official distribution SHA-256. Android
plugins use AGP 9.5.0 and Kotlin 2.4.21; Java/Kotlin bytecode remains targeted
at Java 17. Local Gradle runs use the installed shared gate. CI selects Flutter
3.47.8 and Microsoft Java 25 explicitly and runs app and patch-engine release
unit tests before assembling the signed ARM64 APK.

Flutter 3.47.8 / Dart 3.13.7 includes the Android/Windows TLS certificate remedy
documented in [GHSA-frr6-h895-5pxp](https://github.com/dart-lang/sdk/security/advisories/GHSA-frr6-h895-5pxp).
An SDK update requires rebuilding the APK; changing an SDK version string or
updating the operating system does not replace its compiled engine. Release
preparation rejects an older Dart compiler or mismatched shader/compiler SDKs.

The existing legacy Android DSL and external Kotlin opt-outs remain because the
stable Flutter plugin and several dependencies still consume those APIs. They
are supported compatibility settings for this combination, not acceptance of a
future AGP 10 migration. AGP 9's tested-build-type-only unit-test default is
explicitly disabled to preserve both debug and release components and the
established release verification tasks.

SoLoud 4.1.7 removes 2.1.7's hardcoded NDK 23.1.7779620 and SDK 33 declarations.
Its conventional CMake build uses the AGP NDK default, currently 28.2.13676358,
matching Flutter's app and patch-engine NDK. The older SDK override is removed.
Releases 3.5.4 and 5.2.3 were also inspected: 3.5.4 predates the selected release;
5.2.3 moves native compilation and library resolution into Dart build hooks.
This migration keeps the existing CMake packaging model and audio interface.
This is a migration choice, not a claim that SoLoud 5.2.3 is incompatible.
Plugin CMake staging is checkout-owned under `android/.cxx/<plugin>` so it
does not write native build intermediates into shared Pub package sources.
File Picker 11.0.3 follows Flutter's compile SDK and supports AGP 9. Its public
static API replaces the former `FilePicker.platform` calls. The picker tests use
the normal method-channel contract, including its Standard codec, rather than
the removed platform facade. Versions 9.2.3, 10.3.11, 11.0.3, 12.3.0 and 13.3.2
were inspected; 12/13 introduce a separate federated implementation migration.
The selected 11.0.3 also contains the publisher's Android path-resolution fix.
Under AGP 9 that picker assumes built-in Kotlin. The root project explicitly
applies the selected external Kotlin compiler to this module and retains its
Java 17 target, matching this Flutter stack's declared Kotlin mode.
On Windows, keep the checkout and resolved Pub plugin sources on the same
volume. Kotlin's relocatable incremental cache cannot make a C: plugin source
relative to a D: Android root. For isolated validation, use a process-local
`PUB_CACHE` on the checkout's volume, seed the resolved packages locally, verify
their content, and regenerate bindings with `flutter pub get --offline`. Do not
disable incremental compilation or relocate another consumer's shared cache.

Packaging verification must check the actual APK version, existing signing
certificate, ARM64 payload, and packaged `libflutter.so` against the patched
SDK's exact release engine artifact. Device validation and broader console
feature acceptance remain separate from host toolchain verification.
For nonsplit builds with explicit `target-platform`, native ABI filters follow
that target. A package must not contain other ABI directories without matching
Flutter engine libraries. Split and unspecified-platform builds retain Flutter's
existing selection. The minimum Flutter constraint enforces the patched SDK
without changing the application's existing Dart language version.

For offline host regression runs, select the patched SDK explicitly and set
`RSHOP_TEST_FONT_CACHE` to the existing Google Fonts cache before invoking
`flutter test --no-pub --concurrency=1 --exclude-tags live`. The resolved-cover
and metadata-detail fixtures require cached Outfit 600/700 and Inter regular/600
fonts; without that binding their setup fails before their checks can run.
Keep that prerequisite distinct from a product or SDK regression. Do not fetch
fonts or artwork from a live provider to make an offline fixture pass.
