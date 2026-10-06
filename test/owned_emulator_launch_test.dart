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
  test('mapped Game Gear ZIP keeps its filename and uses the owned RetroArch grant', () async {
    final zip = exactGame('gg-zip', name: 'Game.zip');
    final gg = SystemModel.supportedSystems.singleWhere((s) => s.id == 'gamegear');
    final installed = InstalledArtifact.fromJson({...manifest.toJson(),
      'artifact': zip.remoteArtifact!.toJson(), 'relativePath': 'Game.zip'});
    final launcher = OwnedEmulatorLauncher(romManager: _RomManager(() async => installed), channel: channel);
    expect(RomManager.getTargetFilename(zip, gg), 'Game.zip');
    await launcher.open(zip, gg, '/owned');
    expect(calls.single.method, 'launchOwnedRetroArchGameGear');
    expect(calls.single.arguments, {'installationId': installed.id, 'filename': 'Game.zip'});
    expect(OwnedEmulatorLauncher.supports(zip, system), isFalse);
  });
  test('mapped N64 archives retain their filename and require fresh ownership', () async {
    final n64 = SystemModel.supportedSystems.singleWhere((s) => s.id == 'n64');
    for (final extension in ['7z', 'zip']) {
      calls.clear();
      final archive = exactGame('n64-$extension', name: 'Game.$extension');
      final installed = InstalledArtifact.fromJson({...manifest.toJson(),
        'artifact': archive.remoteArtifact!.toJson(), 'relativePath': archive.filename});
      final launcher = OwnedEmulatorLauncher(romManager: _RomManager(() async => installed), channel: channel);
      expect(RomManager.getTargetFilename(archive, n64), archive.filename);
      await launcher.open(archive, n64, '/owned');
      expect(calls.single.method, 'launchOwnedRetroArchN64');
      expect(calls.single.arguments, {'installationId': installed.id, 'filename': archive.filename});
      expect(OwnedEmulatorLauncher.supports(archive, system), isFalse);
    }
  });
  test('standalone PS1 CHD uses an exact owned RetroArch handoff', () async {
    final psx = SystemModel.supportedSystems.singleWhere((s) => s.id == 'psx');
    final chd = exactGame('psx-chd', name: 'Game.chd');
    final installed = InstalledArtifact.fromJson({...manifest.toJson(),
      'artifact': chd.remoteArtifact!.toJson(), 'relativePath': chd.filename});
    final launcher = OwnedEmulatorLauncher(romManager: _RomManager(() async => installed), channel: channel);
    expect(OwnedEmulatorLauncher.supports(chd, psx), isTrue);
    await launcher.open(chd, psx, '/owned');
    expect(calls.single.method, 'launchOwnedRetroArchPSX');
    expect(calls.single.arguments, {'installationId': installed.id, 'filename': chd.filename});
    for (final extension in ['zip', '7z', 'cue', 'iso', 'pbp']) {
      expect(OwnedEmulatorLauncher.supports(exactGame('other', name: 'Game.$extension'), psx), isFalse);
    }
    final missing = OwnedEmulatorLauncher(romManager: _RomManager(() async => throw StateError('not installed')), channel: channel);
    await expectLater(missing.open(chd, psx, '/owned'), throwsStateError);
    expect(calls, hasLength(1));
  });
  test('standalone PSP CHD requires ownership and uses PPSSPP without path grants', () async {
    final psp = SystemModel.supportedSystems.singleWhere((s) => s.id == 'psp');
    final chd = exactGame('psp-chd', name: 'Game.chd');
    final installed = InstalledArtifact.fromJson({...manifest.toJson(),
      'artifact': chd.remoteArtifact!.toJson(), 'relativePath': chd.filename});
    final launcher = OwnedEmulatorLauncher(romManager: _RomManager(() async => installed), channel: channel);
    expect(OwnedEmulatorLauncher.supports(chd, psp), isTrue);
    await launcher.open(chd, psp, '/owned');
    expect(calls.single.method, 'launchOwnedPPSSPP');
    expect(calls.single.arguments, {'installationId': installed.id, 'filename': chd.filename});
    for (final extension in ['zip', '7z', 'iso', 'cso', 'pbp']) {
      expect(OwnedEmulatorLauncher.supports(exactGame('other', name: 'Game.$extension'), psp), isFalse);
    }
    final missing = OwnedEmulatorLauncher(romManager: _RomManager(() async => throw StateError('not installed')), channel: channel);
    await expectLater(missing.open(chd, psp, '/owned'), throwsStateError);
    expect(calls, hasLength(1));
  });
}
