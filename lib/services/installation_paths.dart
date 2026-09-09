import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

String installationPath(String value) => p.normalize(p.absolute(value));

bool _samePath(String a, String b) {
  if (a == b) return true;
  if (a.toLowerCase() != b.toLowerCase()) return false;
  try {
    // Case folding is only a candidate lookup. Actual object identity decides:
    // differently cased files on a case-sensitive volume remain distinct.
    return FileSystemEntity.identicalSync(a, b);
  } on FileSystemException {
    return false;
  }
}

bool installationPathsOverlap(String a, String b) {
  final left = p.split(installationPath(a));
  final right = p.split(installationPath(b));
  final common = left.length < right.length ? left.length : right.length;
  return _samePath(p.joinAll(left.take(common)), p.joinAll(right.take(common)));
}

/// Constant-depth path lookup with filesystem proof only for case aliases.
class InstallationPathClaims {
  final _targets = <String, Set<String>>{};
  final _parents = <String, Set<String>>{};
  InstallationPathClaims(Iterable<String> paths) {
    for (final path in paths) {
      final normalized = installationPath(path);
      _targets.putIfAbsent(normalized.toLowerCase(), () => {}).add(normalized);
      var parent = p.dirname(normalized);
      while (_parents.putIfAbsent(parent.toLowerCase(), () => {}).add(parent)) {
        final next = p.dirname(parent);
        if (next == parent) break;
        parent = next;
      }
    }
  }

  bool overlaps(String path) {
    var current = installationPath(path);
    if ((_parents[current.toLowerCase()] ?? const <String>{})
        .any((parent) => _samePath(parent, current))) {
      return true;
    }
    while (true) {
      if ((_targets[current.toLowerCase()] ?? const <String>{})
          .any((target) => _samePath(target, current))) {
        return true;
      }
      final next = p.dirname(current);
      if (next == current) return false;
      current = next;
    }
  }
}

/// Main-isolate coordination for target reservation versus legacy tree removal.
/// A reservation commits before publication can start. If removal wins the
/// scope first, reservation waits for it; if reservation wins, removal sees the
/// durable owner and refuses. No database transaction spans filesystem work.
class InstallationMutations {
  static final _active = <_Mutation>[];
  static Future<T> run<T>(String path, Future<T> Function() operation) async {
    final normalized = installationPath(path).toLowerCase();
    while (true) {
      // Conservatively serialize potential case aliases even before creation.
      // This affects scheduling only, never file identity or deletion authority.
      final conflicts = _active
          .where((other) =>
              normalized == other.path ||
              p.isWithin(normalized, other.path) ||
              p.isWithin(other.path, normalized))
          .toList();
      if (conflicts.isEmpty) break;
      await Future.wait(conflicts.map((other) => other.done.future));
    }
    final mutation = _Mutation(normalized);
    _active.add(mutation);
    try {
      return await operation();
    } finally {
      _active.remove(mutation);
      mutation.done.complete();
    }
  }
}

class _Mutation {
  final String path;
  final done = Completer<void>();
  _Mutation(this.path);
}
