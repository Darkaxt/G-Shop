import 'dart:convert';
import 'package:path/path.dart' as p;

class BundleLayoutException implements Exception {
  final String code;
  const BundleLayoutException(this.code);
  @override
  String toString() => 'Bundle layout: $code';
}

/// Only explicit, local UTF-8 M3U and binary CUE dependencies. No inference,
/// downloads during indexing, parent traversal, URLs or archive extraction.
class BundleReferences {
  // Text parsing creates strings/line views as well as protocol bytes. Keep that
  // bounded below the transfer buffer contract, even for adversarial headers.
  static const maxHeaderBytes = 256 * 1024;
  static const maxMembers = 256;
  static bool isManifest(String name) =>
      const ['.m3u', '.cue'].contains(p.posix.extension(name).toLowerCase());

  static String safePath(String path) {
    if (path.isEmpty ||
        path.startsWith('/') ||
        RegExp(r'[\\\x00-\x1f<>:"|?*]').hasMatch(path)) {
      throw const BundleLayoutException('unsafe_path');
    }
    final parts = path.split('/');
    if (parts.any((part) => part.isEmpty || part == '..')) {
      throw const BundleLayoutException('unsafe_path');
    }
    final safe = parts.where((part) => part != '.').join('/');
    if (safe.isEmpty) throw const BundleLayoutException('unsafe_path');
    if (utf8.encode(safe).length > 4096 ||
        safe.split('/').any((part) => utf8.encode(part).length > 255)) {
      throw const BundleLayoutException('unsupported_path');
    }
    return safe;
  }

  static List<String> parse(String name, List<int> bytes) {
    if (!isManifest(name) || bytes.length > maxHeaderBytes) {
      throw const BundleLayoutException('unsupported_layout');
    }
    String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      throw const BundleLayoutException('unsupported_encoding');
    }
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    final result = <String>[];
    final folded = <String, String>{};
    for (final line in const LineSplitter().convert(text)) {
      final value = line.trim();
      if (value.isEmpty) continue;
      String? dependency;
      if (name.toLowerCase().endsWith('.m3u')) {
        if (value.startsWith('#')) continue;
        dependency = value;
      } else {
        if (!RegExp(r'^FILE\b', caseSensitive: false).hasMatch(value)) continue;
        final match = RegExp(r'^FILE\s+(?:"([^"]+)"|(\S+))\s+BINARY\s*$',
                caseSensitive: false)
            .firstMatch(value);
        if (match == null) {
          throw const BundleLayoutException('unsupported_cue_file');
        }
        dependency = match[1] ?? match[2];
      }
      final safe = safePath(dependency!);
      final old = folded[safe.toLowerCase()];
      if (old != null && old != safe) {
        throw const BundleLayoutException('ambiguous_path');
      }
      if (old == null) {
        folded[safe.toLowerCase()] = safe;
        result.add(safe);
        if (result.length > maxMembers) {
          throw const BundleLayoutException('unsupported_layout');
        }
      }
    }
    if (result.isEmpty) {
      throw const BundleLayoutException('missing_dependencies');
    }
    return List.unmodifiable(result);
  }
}
