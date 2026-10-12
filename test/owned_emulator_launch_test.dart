import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/models/game_item.dart';
import 'package:retro_eshop/models/system_model.dart';
import 'package:retro_eshop/models/transfer_record.dart';
import 'package:retro_eshop/models/retroarch_battery_route.dart';
import 'package:retro_eshop/services/owned_emulator_launcher.dart';
import 'package:retro_eshop/services/rom_manager.dart';
import 'drive_exact_identity_runtime_test.dart' show exactGame;

class _RomManager extends RomManager {
  final Future<InstalledArtifact> Function() resolve;
  _RomManager(this.resolve);
  @override
  Future<InstalledArtifact> requireInstalledArtifact(
          GameItem game, String root) =>
      resolve();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('owned-emulator-test');
  final game = exactGame('one', name: 'Game.rvz');
  final system = SystemModel.supportedSystems.singleWhere((s) => s.id == 'gc');
  final manifest = InstalledArtifact(
      id: 'installed-one',
      transferId: 'one',
      artifact: game.remoteArtifact!,
      destinationRoot: '/owned',
      relativePath: 'Game.rvz',
      sizeBytes: 42,
      verifiedChecksums: {'sha256': '0' * 64},
      fileIdentity: NativeFileIdentity(
          volumeId: '1',
          fileId: '2',
          sizeBytes: 42,
          modifiedAt: DateTime.utc(2026)));
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));
  test(
      'hands off only a fresh exact manifest, never a filename path or source token',
      () async {
    final launcher = OwnedEmulatorLauncher(
        romManager: _RomManager(() async => manifest), channel: channel);
    await launcher.open(game, system, '/owned');
    expect(calls.single.method, 'launchOwnedDolphin');
    expect(calls.single.arguments,
        {'installationId': manifest.id, 'filename': manifest.relativePath});
  });
  test('companion component shares the exact preflight and native ROM handoff',
      () async {
    final launcher = OwnedEmulatorLauncher(
        romManager: _RomManager(() async => manifest), channel: channel);
    await launcher.open(game, system, '/owned',
        companionComponent: 'com.example.reader/.MainActivity');
    expect(calls.single.method, 'launchOwnedDolphin');
    expect(calls.single.arguments, {
      'installationId': manifest.id,
      'filename': manifest.relativePath,
      'companionComponent': 'com.example.reader/.MainActivity',
    });
  });
  test('paired repeated activation joins the same pending preflight', () async {
    final gate = Completer<InstalledArtifact>();
    final launcher = OwnedEmulatorLauncher(
        romManager: _RomManager(() => gate.future), channel: channel);
    final first = launcher.open(game, system, '/owned',
        companionComponent: 'com.example.reader/.MainActivity');
    final second = launcher.open(game, system, '/owned',
        companionComponent: 'com.example.reader/.MainActivity');
    gate.complete(manifest);
    await Future.wait([first, second]);
    expect(calls, hasLength(1));
  });
  test('pre-launch save preparation finishes before a single emulator handoff',
      () async {
    final entered = Completer<void>();
    final ready = Completer<void>();
    var preparations = 0;
    final launcher = OwnedEmulatorLauncher(
        romManager: _RomManager(() async => manifest), channel: channel);
    Future<void> prepare() async {
      preparations++;
      entered.complete();
      await ready.future;
    }

    final first = launcher.open(game, system, '/owned', prepareSave: prepare);
    final second = launcher.open(game, system, '/owned', prepareSave: prepare);
    await entered.future;
    expect(calls, isEmpty);
    ready.complete();
    await Future.wait([first, second]);
    expect(preparations, 1);
    expect(calls, hasLength(1));
  });
  test('pre-launch save conflict prevents emulator and companion handoff',
      () async {
    final launcher = OwnedEmulatorLauncher(
        romManager: _RomManager(() async => manifest), channel: channel);
    await expectLater(
        launcher.open(game, system, '/owned',
            companionComponent: 'com.example.reader/.MainActivity',
            prepareSave: () async =>
                throw PlatformException(code: 'save_conflict')),
        throwsA(isA<PlatformException>()));
    expect(calls, isEmpty);
  });
  test('rejects missing ownership before any emulator call', () async {
    final launcher = OwnedEmulatorLauncher(
        romManager: _RomManager(() async => throw StateError('not installed')),
        channel: channel);
    await expectLater(launcher.open(game, system, '/owned'), throwsStateError);
    expect(calls, isEmpty);
  });
  test('save review shares exact GBA grant preflight without launching',
      () async {
    final gba = SystemModel.supportedSystems.singleWhere((s) => s.id == 'gba');
    final archive = exactGame('gba-save', name: 'Game.7z');
    final installed = InstalledArtifact.fromJson({
      ...manifest.toJson(),
      'artifact': archive.remoteArtifact!.toJson(),
      'relativePath': archive.filename
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return 'installed-one%2FGame.srm';
    });
    final launcher = OwnedEmulatorLauncher(
        romManager: _RomManager(() async => installed), channel: channel);
    expect(await launcher.reviewRetroArchGbaSave(archive, gba, '/owned'),
        'installed-one%2FGame.srm');
    expect(calls.single.method, 'reviewOwnedRetroArchGameBoyAdvanceSave');
    expect(calls.single.arguments,
        {'installationId': installed.id, 'filename': archive.filename});
    final missing = OwnedEmulatorLauncher(
        romManager: _RomManager(() async => throw StateError('not installed')),
        channel: channel);
    await expectLater(missing.reviewRetroArchGbaSave(archive, gba, '/owned'),
        throwsStateError);
    expect(calls, hasLength(1));
  });
  test('repeated activation joins the same handoff instead of opening twice',
      () async {
    final gate = Completer<InstalledArtifact>();
    final launcher = OwnedEmulatorLauncher(
        romManager: _RomManager(() => gate.future), channel: channel);
    final first = launcher.open(game, system, '/owned');
    final second = launcher.open(game, system, '/owned');
    gate.complete(manifest);
    await Future.wait([first, second]);
    expect(calls, hasLength(1));
  });
  test('archive and unsupported console never reach the handoff', () async {
    final launcher = OwnedEmulatorLauncher(
        romManager: _RomManager(() async => manifest), channel: channel);
    await expectLater(
        launcher.open(exactGame('zip', name: 'Game.7z'), system, '/owned'),
        throwsUnsupportedError);
    await expectLater(
        launcher.open(game, SystemModel.supportedSystems.first, '/owned'),
        throwsUnsupportedError);
    expect(calls, isEmpty);
  });
  test(
      'mapped Game Gear ZIP keeps its filename and uses the owned RetroArch grant',
      () async {
    final zip = exactGame('gg-zip', name: 'Game.zip');
    final gg =
        SystemModel.supportedSystems.singleWhere((s) => s.id == 'gamegear');
    final installed = InstalledArtifact.fromJson({
      ...manifest.toJson(),
      'artifact': zip.remoteArtifact!.toJson(),
      'relativePath': 'Game.zip'
    });
    final launcher = OwnedEmulatorLauncher(
        romManager: _RomManager(() async => installed), channel: channel);
    expect(RomManager.getTargetFilename(zip, gg), 'Game.zip');
    await launcher.open(zip, gg, '/owned');
    expect(calls.single.method, 'launchOwnedRetroArchGameGear');
    expect(calls.single.arguments,
        {'installationId': installed.id, 'filename': 'Game.zip'});
    expect(OwnedEmulatorLauncher.supports(zip, system), isFalse);
  });
  test('Game Gear save review uses the exact owned ZIP without launching',
      () async {
    final gg =
        SystemModel.supportedSystems.singleWhere((s) => s.id == 'gamegear');
    final zip = exactGame('gg-save', name: 'Game.zip');
    final installed = InstalledArtifact.fromJson({
      ...manifest.toJson(),
      'artifact': zip.remoteArtifact!.toJson(),
      'relativePath': zip.filename,
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return 'installed-one%2FGame.srm';
    });
    final launcher = OwnedEmulatorLauncher(
        romManager: _RomManager(() async => installed), channel: channel);
    expect(await launcher.reviewRetroArchGameGearSave(zip, gg, '/owned'),
        'installed-one%2FGame.srm');
    expect(calls.single.method, 'reviewOwnedRetroArchGameGearSave');
    expect(calls.single.arguments, {
      'installationId': installed.id,
      'filename': zip.filename,
    });
    await expectLater(
        launcher.reviewRetroArchGameGearSave(zip, system, '/owned'),
        throwsUnsupportedError);
    expect(calls, hasLength(1));
  });
  for (final (route, method) in [
    (
      RetroArchBatteryRoute.masterSystem,
      'reviewOwnedRetroArchMasterSystemSave'
    ),
    (RetroArchBatteryRoute.megaDrive, 'reviewOwnedRetroArchMegaDriveSave'),
  ]) {
    test('${route.platformId} save review uses the launch-bound ZIP name',
        () async {
      final console = SystemModel.supportedSystems
          .singleWhere((system) => system.id == route.platformId);
      final zip = exactGame('sega-save', name: 'Game.zip');
      final installed = InstalledArtifact.fromJson({
        ...manifest.toJson(),
        'artifact': zip.remoteArtifact!.toJson(),
        'relativePath': zip.filename,
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return 'installed-one%2FGame.srm';
      });
      final launcher = OwnedEmulatorLauncher(
          romManager: _RomManager(() async => installed), channel: channel);
      expect(
          await launcher.reviewRetroArchBatterySave(
              zip, console, '/owned', route),
          'installed-one%2FGame.srm');
      expect(calls.single.method, method);
      expect(calls.single.arguments, {
        'installationId': installed.id,
        'filename': zip.filename,
      });
      await expectLater(
          launcher.reviewRetroArchBatterySave(zip, system, '/owned', route),
          throwsUnsupportedError);
      expect(calls, hasLength(1));
    });
  }
  test('mapped N64 archives retain their filename and require fresh ownership',
      () async {
    final n64 = SystemModel.supportedSystems.singleWhere((s) => s.id == 'n64');
    for (final extension in ['7z', 'zip']) {
      calls.clear();
      final archive = exactGame('n64-$extension', name: 'Game.$extension');
      final installed = InstalledArtifact.fromJson({
        ...manifest.toJson(),
        'artifact': archive.remoteArtifact!.toJson(),
        'relativePath': archive.filename
      });
      final launcher = OwnedEmulatorLauncher(
          romManager: _RomManager(() async => installed), channel: channel);
      expect(RomManager.getTargetFilename(archive, n64), archive.filename);
      await launcher.open(archive, n64, '/owned');
      expect(calls.single.method, 'launchOwnedRetroArchN64');
      expect(calls.single.arguments,
          {'installationId': installed.id, 'filename': archive.filename});
      expect(OwnedEmulatorLauncher.supports(archive, system), isFalse);
    }
  });
  for (final (platform, method) in [
    ('megadrive', 'launchOwnedRetroArchMegaDrive'),
    ('mastersystem', 'launchOwnedRetroArchMasterSystem'),
    ('sg1000', 'launchOwnedRetroArchSG1000'),
  ]) {
    test(
        '$platform Sega ZIP uses the exact console handoff and retains its archive',
        () async {
      final mapped =
          SystemModel.supportedSystems.singleWhere((s) => s.id == platform);
      final zip = exactGame('$platform-zip', name: 'Game.zip');
      final installed = InstalledArtifact.fromJson({
        ...manifest.toJson(),
        'artifact': zip.remoteArtifact!.toJson(),
        'relativePath': zip.filename
      });
      final launcher = OwnedEmulatorLauncher(
          romManager: _RomManager(() async => installed), channel: channel);
      expect(RomManager.getTargetFilename(zip, mapped), zip.filename);
      expect(OwnedEmulatorLauncher.supports(zip, mapped), isTrue);
      await launcher.open(zip, mapped, '/owned');
      expect(calls.single.method, method);
      expect(calls.single.arguments,
          {'installationId': installed.id, 'filename': zip.filename});
      expect(
          OwnedEmulatorLauncher.supports(
              exactGame('other', name: 'Game.7z'), mapped),
          isFalse);
      final missing = OwnedEmulatorLauncher(
          romManager:
              _RomManager(() async => throw StateError('not installed')),
          channel: channel);
      await expectLater(missing.open(zip, mapped, '/owned'), throwsStateError);
      expect(calls, hasLength(1));
    });
  }
  test(
      'mapped Game Boy 7z requires ownership and uses the exact RetroArch leaf route',
      () async {
    final gb = SystemModel.supportedSystems.singleWhere((s) => s.id == 'gb');
    final archive = exactGame('gb-7z', name: 'Game.7z');
    final installed = InstalledArtifact.fromJson({
      ...manifest.toJson(),
      'artifact': archive.remoteArtifact!.toJson(),
      'relativePath': archive.filename
    });
    final launcher = OwnedEmulatorLauncher(
        romManager: _RomManager(() async => installed), channel: channel);
    expect(RomManager.getTargetFilename(archive, gb), archive.filename);
    expect(OwnedEmulatorLauncher.supports(archive, gb), isTrue);
    await launcher.open(archive, gb, '/owned');
    expect(calls.single.method, 'launchOwnedRetroArchGameBoy');
    expect(calls.single.arguments,
        {'installationId': installed.id, 'filename': archive.filename});
    expect(
        OwnedEmulatorLauncher.supports(exactGame('zip', name: 'Game.zip'), gb),
        isFalse);
    for (final id in ['gc']) {
      expect(
          OwnedEmulatorLauncher.supports(archive,
              SystemModel.supportedSystems.singleWhere((s) => s.id == id)),
          isFalse);
    }
    final missing = OwnedEmulatorLauncher(
        romManager: _RomManager(() async => throw StateError('not installed')),
        channel: channel);
    await expectLater(missing.open(archive, gb, '/owned'), throwsStateError);
    expect(calls, hasLength(1));
  });
  for (final (platform, method) in [
    ('gbc', 'launchOwnedRetroArchGameBoyColor'),
    ('gba', 'launchOwnedRetroArchGameBoyAdvance'),
    ('nes', 'launchOwnedRetroArchNes'),
    ('snes', 'launchOwnedRetroArchSnes'),
  ]) {
    test('mapped $platform 7z keeps an exact owned console-specific handoff',
        () async {
      final system =
          SystemModel.supportedSystems.singleWhere((s) => s.id == platform);
      final archive = exactGame('$platform-7z', name: 'Game.7z');
      final installed = InstalledArtifact.fromJson({
        ...manifest.toJson(),
        'artifact': archive.remoteArtifact!.toJson(),
        'relativePath': archive.filename
      });
      final launcher = OwnedEmulatorLauncher(
          romManager: _RomManager(() async => installed), channel: channel);
      expect(OwnedEmulatorLauncher.supports(archive, system), isTrue);
      await launcher.open(archive, system, '/owned');
      expect(calls.single.method, method);
      expect(calls.single.arguments,
          {'installationId': installed.id, 'filename': archive.filename});
      expect(
          OwnedEmulatorLauncher.supports(
              exactGame('zip', name: 'Game.zip'), system),
          isFalse);
      final missing = OwnedEmulatorLauncher(
          romManager:
              _RomManager(() async => throw StateError('not installed')),
          channel: channel);
      await expectLater(
          missing.open(archive, system, '/owned'), throwsStateError);
      expect(calls, hasLength(1));
    });
  }
  test('standalone PS1 CHD uses an exact owned RetroArch handoff', () async {
    final psx = SystemModel.supportedSystems.singleWhere((s) => s.id == 'psx');
    final chd = exactGame('psx-chd', name: 'Game.chd');
    final installed = InstalledArtifact.fromJson({
      ...manifest.toJson(),
      'artifact': chd.remoteArtifact!.toJson(),
      'relativePath': chd.filename
    });
    final launcher = OwnedEmulatorLauncher(
        romManager: _RomManager(() async => installed), channel: channel);
    expect(OwnedEmulatorLauncher.supports(chd, psx), isTrue);
    await launcher.open(chd, psx, '/owned');
    expect(calls.single.method, 'launchOwnedRetroArchPSX');
    expect(calls.single.arguments,
        {'installationId': installed.id, 'filename': chd.filename});
    for (final extension in ['zip', '7z', 'cue', 'iso', 'pbp']) {
      expect(
          OwnedEmulatorLauncher.supports(
              exactGame('other', name: 'Game.$extension'), psx),
          isFalse);
    }
    final missing = OwnedEmulatorLauncher(
        romManager: _RomManager(() async => throw StateError('not installed')),
        channel: channel);
    await expectLater(missing.open(chd, psx, '/owned'), throwsStateError);
    expect(calls, hasLength(1));
  });
  test(
      'standalone PS2 CHD requires ownership and uses the NetherSX2 leaf route',
      () async {
    final ps2 = SystemModel.supportedSystems.singleWhere((s) => s.id == 'ps2');
    final chd = exactGame('ps2-chd', name: 'Game.chd');
    final installed = InstalledArtifact.fromJson({
      ...manifest.toJson(),
      'artifact': chd.remoteArtifact!.toJson(),
      'relativePath': chd.filename
    });
    final launcher = OwnedEmulatorLauncher(
        romManager: _RomManager(() async => installed), channel: channel);
    expect(OwnedEmulatorLauncher.supports(chd, ps2), isTrue);
    await launcher.open(chd, ps2, '/owned');
    expect(calls.single.method, 'launchOwnedNetherSX2');
    expect(calls.single.arguments,
        {'installationId': installed.id, 'filename': chd.filename});
    for (final extension in ['zip', '7z', 'iso', 'cue', 'm3u']) {
      expect(
          OwnedEmulatorLauncher.supports(
              exactGame('other', name: 'Game.$extension'), ps2),
          isFalse);
    }
    final missing = OwnedEmulatorLauncher(
        romManager: _RomManager(() async => throw StateError('not installed')),
        channel: channel);
    await expectLater(missing.open(chd, ps2, '/owned'), throwsStateError);
    expect(calls, hasLength(1));
  });
  test(
      'standalone PSP CHD requires ownership and uses PPSSPP without path grants',
      () async {
    final psp = SystemModel.supportedSystems.singleWhere((s) => s.id == 'psp');
    final chd = exactGame('psp-chd', name: 'Game.chd');
    final installed = InstalledArtifact.fromJson({
      ...manifest.toJson(),
      'artifact': chd.remoteArtifact!.toJson(),
      'relativePath': chd.filename
    });
    final launcher = OwnedEmulatorLauncher(
        romManager: _RomManager(() async => installed), channel: channel);
    expect(OwnedEmulatorLauncher.supports(chd, psp), isTrue);
    await launcher.open(chd, psp, '/owned');
    expect(calls.single.method, 'launchOwnedPPSSPP');
    expect(calls.single.arguments,
        {'installationId': installed.id, 'filename': chd.filename});
    for (final extension in ['zip', '7z', 'iso', 'cso', 'pbp']) {
      expect(
          OwnedEmulatorLauncher.supports(
              exactGame('other', name: 'Game.$extension'), psp),
          isFalse);
    }
    final missing = OwnedEmulatorLauncher(
        romManager: _RomManager(() async => throw StateError('not installed')),
        channel: channel);
    await expectLater(missing.open(chd, psp, '/owned'), throwsStateError);
    expect(calls, hasLength(1));
  });
  test('standalone Wii U WUA requires ownership and exact Cemu handoff',
      () async {
    final wiiu =
        SystemModel.supportedSystems.singleWhere((s) => s.id == 'wiiu');
    final wua = exactGame('wiiu-wua', name: 'Game.wua');
    final installed = InstalledArtifact.fromJson({
      ...manifest.toJson(),
      'artifact': wua.remoteArtifact!.toJson(),
      'relativePath': wua.filename
    });
    final launcher = OwnedEmulatorLauncher(
        romManager: _RomManager(() async => installed), channel: channel);
    expect(OwnedEmulatorLauncher.supports(wua, wiiu), isTrue);
    await launcher.open(wua, wiiu, '/owned');
    expect(calls.single.method, 'launchOwnedCemu');
    expect(calls.single.arguments,
        {'installationId': installed.id, 'filename': wua.filename});
    for (final extension in ['zip', '7z', 'wud', 'wux', 'rpx', 'm3u']) {
      expect(
          OwnedEmulatorLauncher.supports(
              exactGame('other', name: 'Game.$extension'), wiiu),
          isFalse);
    }
    expect(OwnedEmulatorLauncher.supports(wua, system), isFalse);
    final missing = OwnedEmulatorLauncher(
        romManager: _RomManager(() async => throw StateError('not installed')),
        channel: channel);
    await expectLater(missing.open(wua, wiiu, '/owned'), throwsStateError);
    expect(calls, hasLength(1));
  });
}
