# Native ROM patch engine

This module vendors UniPatcher's kernels at
`6f44fa5522f7606e73adc28f2601ef441c164d96` with the pinned native sources listed
in `assets/patch_engine_licenses/NOTICE.txt`. No upstream build or dependency
download script is executed. Combined distribution is GPL-3.0-or-later; the
repository's original MIT licence and third-party grants remain preserved.

R-Shop replaces Android presentation helpers with a headless private-job resource
adapter, streaming I/O, cancellation observation and explicit close-failure
reporting. Kernels retain their original headers. Native XDelta file descriptors
and allocated decoder state are closed on errors, and C type sizes follow the
target ABI. Native compilation has a one-job Ninja pool. Algorithm memory is
bounded by upstream windows; archive extraction sets a 64 MiB SevenZ decoder
memory limit and extracts only the declared exact member and size.

The engine never accepts cloud URLs or downloaded executables. Original and
patch bytes are fingerprinted before invocation. Output is private scratch until
the normal exact-file installation journal verifies and publishes it. EBP's
canonical-base adjustments require an explicit recorded preparation option.
Cancellation joins actual completion (JNI decoding is not forcibly interrupted).

Focused JVM fixtures use synthetic bytes and the pinned upstream test corpus.
The EBP positive test additionally accepts `RSHOP_EBP_BASE`, an owner-supplied
canonical raw EarthBound base; it checks the engine's required MD5 before use.
Without that private file it is explicitly skipped, never claimed as positive
EBP acceptance. No game bytes are included in the source or test resources.
