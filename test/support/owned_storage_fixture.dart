import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Shared native-boundary fixture; production journals and verifiers stay real.
class NativeFileFixture {
  final int inode;
  List<int> bytes = [];
  int stamp = 0;
  NativeFileFixture(this.inode);
  Map<String, Object> get identity => {
        'device': '1',
        'inode': '$inode',
        'size': bytes.length,
        'modifiedSeconds': 100,
        'modifiedNanos': stamp,
      };
}

class _FixtureSession {
  final String stage;
  final String target;
  final NativeFileFixture source;
  bool published;
  NativeFileFixture? copy;
  _FixtureSession(this.stage, this.target, this.source, this.published);
}

class OwnedStorageFixture {
  final files = <String, NativeFileFixture>{};
  final sessions = <String, _FixtureSession>{};
  final methods = <String>[];
  final MethodChannel channel = const MethodChannel('engine-fixture-storage');
  bool copyOnly = false;
  bool invalidArchive = false;
  bool crossMount = false;
  int next = 0;
  Future<void> Function(MethodCall)? before;
  Future<void> Function(MethodCall)? after;
  String Function(String)? canonicalRoot;
  void install() =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, handle);
  Future<Object?> handle(MethodCall call) async {
    methods.add(call.method);
    await before?.call(call);
    final result = execute(call);
    await after?.call(call);
    return result;
  }

  Never fail(String code) => throw PlatformException(code: code);
  Object? execute(MethodCall call) {
    final a = Map<String, dynamic>.from(call.arguments as Map);
    if (call.method == 'ownedPrepare') {
      return {
        'destinationRoot': canonicalRoot?.call(a['destinationRoot'] as String) ??
            a['destinationRoot'],
        'stageRoot': '/owned',
        'destinationVolume': '1',
        'stageVolume': '1',
        'destinationMount': '10',
        'stageMount': crossMount ? '11' : '10',
        'destinationFreeBytes': 1 << 30,
        'stageFreeBytes': 1 << 30
      };
    }
    final stage = a['stagePath'] as String?;
    final target = '${a['destinationRoot']}/${a['relativePath']}';
    if (call.method == 'ownedInspect') {
      return files[a['published'] == true ? target : stage]?.identity;
    }
    if (call.method == 'ownedQuarantine' ||
        call.method == 'ownedRetireQuarantine') {
      if (sessions.values.any((s) => s.stage == stage || s.target == target)) {
        fail('collision');
      }
      final existing = files[stage];
      if (call.method == 'ownedRetireQuarantine' && existing == null) {
        return null;
      }
      final file = existing ?? files[target] ?? fail('changed');
      if (file.identity.toString() !=
          Map<String, Object>.from(a['expectedIdentity']).toString()) {
        fail('changed');
      }
      if (call.method == 'ownedRetireQuarantine') {
        files.remove(stage);
        return null;
      }
      if (existing == null) files[stage!] = files.remove(target)!;
      return file.identity;
    }
    if (call.method == 'ownedRetireStage') {
      if (sessions.values.any((s) => s.stage == stage || s.target == target)) {
        fail('collision');
      }
      final installed = files[target] ?? fail('changed');
      if (installed.identity.toString() !=
          Map<String, Object>.from(a['installedIdentity']).toString()) {
        fail('changed');
      }
      final pending = files[stage];
      if (pending != null &&
          pending.identity.toString() !=
              Map<String, Object>.from(a['expectedIdentity']).toString()) {
        fail('changed');
      }
      files.remove(stage);
      return null;
    }
    if (call.method == 'ownedOpen') {
      final published = a['mode'] == 'published';
      final path = published ? target : stage!;
      if (a['mode'] == 'create') {
        if (files.containsKey(path)) fail('collision');
        files[path] = NativeFileFixture(++next);
      }
      final file = files[path] ?? fail('not_found');
      if (a['expectedIdentity'] != null) {
        if (file.identity['inode'] != a['expectedIdentity']['inode'] ||
            file.bytes.length < (a['durableOffset'] as int)) {
          fail('changed');
        }
        if (published || a['mode'] == 'quarantine') {
          if (file.identity.toString() !=
                  Map<String, Object>.from(a['expectedIdentity']).toString() ||
              a['durableOffset'] != file.bytes.length) {
            fail('changed');
          }
        } else if (file.bytes.length != a['durableOffset']) {
          file.bytes = file.bytes.sublist(0, a['durableOffset'] as int);
          file.stamp++;
        }
      }
      final id = 'session-${++next}';
      sessions[id] = _FixtureSession(stage!, target, file, published);
      return {'session': id, 'identity': file.identity};
    }
    if (call.method == 'ownedClose') {
      sessions.remove(a['session']);
      return null;
    }
    final s = sessions[a['session']] ?? fail('closed');
    switch (call.method) {
      case 'ownedValidateGameGearZip':
      case 'ownedValidateSegaZip':
      case 'ownedValidateN64SevenZip':
      case 'ownedValidateGameBoySevenZip':
      case 'ownedValidateGameBoyColorSevenZip':
      case 'ownedValidateGameBoyAdvanceSevenZip':
      case 'ownedValidateN64Zip':
      case 'ownedValidateDsSevenZip':
      case 'ownedValidateDsZip':
        if (invalidArchive) fail('unsupported_archive');
        return null;
      case 'ownedWrite':
        if (s.published || s.source.bytes.length != a['offset']) {
          fail('changed');
        }
        s.source.bytes.addAll(a['bytes'] as Uint8List);
        s.source.stamp++;
        return null;
      case 'ownedCheckpoint':
        return s.source.identity;
      case 'ownedRead':
        return Uint8List.fromList(s.source.bytes.sublist(
            a['offset'] as int, (a['offset'] as int) + (a['length'] as int)));
      case 'ownedPublish':
        if (copyOnly) fail('unsupported');
        if (files.containsKey(s.target)) fail('collision');
        files[s.target] = files.remove(s.stage)!;
        s.published = true;
        return s.source.identity;
      case 'ownedCopyOpen':
        if (a['destinationIdentity'] == null) {
          if (files.containsKey(s.target)) fail('collision');
          files[s.target] = NativeFileFixture(++next);
        }
        final copy = files[s.target] ?? fail('not_found');
        if (copy.bytes.length != a['durableOffset'] ||
            (a['destinationIdentity'] != null &&
                copy.identity['inode'] != a['destinationIdentity']['inode'])) {
          fail('changed');
        }
        s.copy = copy;
        return copy.identity;
      case 'ownedCopyValidatePrefix':
        final end = (a['offset'] as int) + (a['length'] as int);
        if (s.copy!.bytes.sublist(0, end).toString() !=
            s.source.bytes.sublist(0, end).toString()) {
          fail('changed');
        }
        return end;
      case 'ownedCopyChunk':
        final end = (a['offset'] as int) + (a['length'] as int);
        s.copy!.bytes.addAll(s.source.bytes.sublist(a['offset'] as int, end));
        s.copy!.stamp++;
        return end;
      case 'ownedCopyCheckpoint':
      case 'ownedCopyFinish':
        return s.copy!.identity;
      case 'ownedCopyRead':
        return Uint8List.fromList(s.copy!.bytes.sublist(
            a['offset'] as int, (a['offset'] as int) + (a['length'] as int)));
      default:
        fail('invalid_arguments');
    }
  }
}
