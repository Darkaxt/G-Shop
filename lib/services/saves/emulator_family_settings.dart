import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/emulator_family_registry.dart';

/// The shared file is the authority. Preferences hold only a validated recovery
/// snapshot, so an unfinished external edit never breaks package discovery.
class EmulatorFamilySettings {
  static const androidPath =
      '/storage/emulated/0/RShop/config/emulator_families.json';
  static const recoveryKey = 'emulator_families_last_valid_v1';
  final File file;
  final SharedPreferences _preferences;
  EmulatorFamilyRegistry registry;
  String? issue;
  String? _source;

  EmulatorFamilySettings._(this.file, this._preferences, this.registry);

  static Future<EmulatorFamilySettings> open({
    File? file,
    SharedPreferences? preferences,
    AssetBundle? bundle,
  }) async {
    final defaults = await EmulatorFamilyRegistry.load(bundle: bundle);
    final prefs = preferences ?? await SharedPreferences.getInstance();
    final path = file ??
        File(Platform.isAndroid
            ? androidPath
            : '${(await getApplicationDocumentsDirectory()).path}/RShop/config/emulator_families.json');
    var recovered = defaults;
    final saved = prefs.getString(recoveryKey);
    if (saved != null) {
      try {
        recovered = EmulatorFamilyRegistry.decode(saved);
      } on FormatException {
        // This cache is not the authority and cannot replace a user's file.
      }
    }
    final settings = EmulatorFamilySettings._(path, prefs, recovered);
    try {
      path.parent.createSync(recursive: true);
      if (!path.existsSync()) {
        // Exclusive creation does not replace an externally created file.
        path.createSync(exclusive: true);
        path.writeAsStringSync(defaults.encode(), flush: true);
      }
    } on FileSystemException {
      // Read the file if another creator won, or report unavailable storage.
    }
    await settings.reload();
    return settings;
  }

  String _read() {
    // Configuration is small and bounded, not ROM/save payload IO. Read at most
    // the limit plus one byte, including when an external editor grows the file.
    final handle = file.openSync();
    try {
      final bytes = handle.readSync(EmulatorFamilyRegistry.maxBytes + 1);
      if (bytes.length > EmulatorFamilyRegistry.maxBytes) {
        throw const FormatException('Emulator configuration is too large');
      }
      return utf8.decode(bytes);
    } finally {
      handle.closeSync();
    }
  }

  Future<void> reload() async {
    try {
      final source = _read();
      final parsed = EmulatorFamilyRegistry.decode(source);
      // Publish this read before awaiting cache IO. A later file event must not
      // be overwritten when an earlier cache write completes.
      registry = parsed;
      _source = source;
      issue = null;
      if (!await _preferences.setString(recoveryKey, parsed.encode())) {
        throw StateError('The last working configuration could not be saved.');
      }
    } on FormatException {
      issue =
          'Check the emulator settings file. Using the last working settings.';
    } on FileSystemException {
      issue = 'Cannot read the shared settings file. Check storage access.';
    }
  }

  /// The dialog edits its opening snapshot, never silently replacing newer edits.
  Future<void> save(EmulatorFamilyRegistry replacement,
      {required String expectedSource}) async {
    if (_read() != expectedSource) {
      await reload();
      throw StateError('Settings changed outside the app. Reopen the dialog.');
    }
    final pending = File('${file.path}.pending');
    // Reserved app-write scratch, never a second configuration authority. The
    // synchronous write/rename has no yield point; this can only be a remnant
    // of an interrupted earlier write, not another in-isolate active writer.
    if (pending.existsSync()) pending.deleteSync();
    pending.createSync(exclusive: true);
    try {
      pending.writeAsStringSync(replacement.encode(), flush: true);
      if (_read() != expectedSource) {
        await reload();
        throw StateError(
            'Settings changed outside the app. Reopen the dialog.');
      }
      pending.renameSync(file.path);
    } finally {
      if (pending.existsSync()) pending.deleteSync();
    }
    await reload();
  }

  String get source {
    if (issue != null || _source == null) {
      throw StateError(
          'Fix the shared settings file before editing in the app.');
    }
    return _source!;
  }

  Stream<FileSystemEvent> watch() => file.parent.watch().where((event) =>
      !(event is FileSystemModifyEvent && !event.contentChanged) &&
      (p.equals(event.path, file.path) ||
          event is FileSystemMoveEvent &&
              event.destination != null &&
              p.equals(event.destination!, file.path)));
}
