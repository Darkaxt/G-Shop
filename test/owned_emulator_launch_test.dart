import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/models/game_item.dart';
import 'package:retro_eshop/models/system_model.dart';
import 'package:retro_eshop/models/transfer_record.dart';
import 'package:retro_eshop/services/owned_emulator_launcher.dart';
import 'package:retro_eshop/services/rom_manager.dart';
import 'drive_exact_identity_runtime_test.dart' show exactGame;

class _RomManager extends RomManager {
  final Future<InstalledArtifact> Function() resolve;
  _RomManager(this.resolve);
  @override
  Future<InstalledArtifact> requireInstalledArtifact(GameItem game, String root) => resolve();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('owned-emulator-test');
  final game = exactGame('one', name: 'Game.rvz');
  final system = SystemModel.supportedSystems.singleWhere((s) => s.id == 'gc');
  final manifest = InstalledArtifact(id: 'installed-one', transferId: 'one',
      artifact: game.remoteArtifact!, destinationRoot: '/owned', relativePath: 'Game.rvz',
      sizeBytes: 42, verifiedChecksums: {'sha256': '0' * 64},
      fileIdentity: NativeFileIdentity(volumeId: '1', fileId: '2', sizeBytes: 42,
          modifiedAt: DateTime.utc(2026)));
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async { calls.add(call); return null; });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));
  test('hands off only a fresh exact manifest, never a filename path or source token', () async {
    final launcher = OwnedEmulatorLauncher(romManager: _RomManager(() async => manifest), channel: channel);
    await launcher.open(game, system, '/owned');
    expect(calls.single.method, 'launchOwnedDolphin');
    expect(calls.single.arguments, {'installationId': manifest.id, 'filename': manifest.relativePath});
  });
  test('rejects missing ownership before any emulator call', () async {
    final launcher = OwnedEmulatorLauncher(romManager: _RomManager(() async => throw StateError('not installed')), channel: channel);
    await expectLater(launcher.open(game, system, '/owned'), throwsStateError);
    expect(calls, isEmpty);
  });
  test('repeated activation joins the same handoff instead of opening twice', () async {
    final gate = Completer<InstalledArtifact>();
    final launcher = OwnedEmulatorLauncher(romManager: _RomManager(() => gate.future), channel: channel);
    final first = launcher.open(game, system, '/owned');
    final second = launcher.open(game, system, '/owned');
    gate.complete(manifest);
    await Future.wait([first, second]);
    expect(calls, hasLength(1));
  });
  test('archive and unsupported console never reach the handoff', () async {
    final launcher = OwnedEmulatorLauncher(romManager: _RomManager(() async => manifest), channel: channel);
    await expectLater(launcher.open(exactGame('zip', name: 'Game.7z'), system, '/owned'), throwsUnsupportedError);
    await expectLater(launcher.open(game, SystemModel.supportedSystems.first, '/owned'), throwsUnsupportedError);
    expect(calls, isEmpty);
  });
}
