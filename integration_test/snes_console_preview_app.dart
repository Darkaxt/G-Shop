// Bounded native selector proof; no library, account or publication startup.
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:g_shop/core/theme/app_theme.dart';
import 'package:g_shop/features/preview/console_preview_host.dart';
import 'package:g_shop/features/preview/dual_screen_preview_host.dart';
import 'package:g_shop/features/preview/preview_screen.dart' as secondary;
import 'package:g_shop/models/socket_media_model.dart';
import 'package:g_shop/models/system_model.dart';
import 'package:g_shop/providers/app_providers.dart';
import 'package:g_shop/providers/preview_providers.dart';
import 'package:g_shop/services/secondary_preview.dart';
import 'package:g_shop/services/socket_media_import.dart';
import 'package:g_shop/services/storage_service.dart';

Future<void> guard() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kDebugMode ||
      !Platform.isAndroid ||
      (await PackageInfo.fromPlatform()).packageName !=
          'com.darkaxt.rshop.sharedproof') {
    throw StateError('SNES proof requires its isolated debug package');
  }
}

@pragma('vm:entry-point')
Future<void> previewMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The secondary engine registers only the preview channels, so it has no
  // package_info plugin. The main engine checks the isolated package before
  // creating this renderer; keep the debug-only guard here as well.
  if (!kDebugMode || !Platform.isAndroid) {
    throw StateError('SNES proof renderer requires its debug Android host');
  }
  SocketMediaModel.importedBundle = SocketMediaDirectoryBundle(
      Directory('/storage/emulated/0/GShopSnesPreview-20261029/environment'));
  await SocketMediaModel
      .loadEnvironment(); // Real imported HDR checksum/identity.
  await secondary.previewMain();
}

Future<void> main() async {
  await guard();
  final storage = StorageService();
  await storage.init();
  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.landscapeLeft]);
  runApp(ProviderScope(overrides: [
    storageServiceProvider.overrideWithValue(storage),
    secondaryPreviewProvider.overrideWith((ref) {
      final bridge = SecondaryPreview();
      bridge.prepare(enabled: true);
      return bridge;
    }),
  ], child: const Proof()));
}

class Proof extends ConsumerStatefulWidget {
  const Proof({super.key});
  @override
  ConsumerState<Proof> createState() => _ProofState();
}

class _ProofState extends ConsumerState<Proof> {
  bool selected = true;
  @override
  Widget build(BuildContext context) => MaterialApp(
      theme: AppTheme.darkTheme,
      navigatorObservers: [previewRouteObserver],
      home: ConsolePreviewHost(
          system: selected
              ? SystemModel.supportedSystems.firstWhere((s) => s.id == 'snes')
              : null,
          child: Scaffold(
              body: Center(
                  child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('SNES console preview — isolated native validation'),
              const Text(
                  'Production ConsolePreviewHost and secondary renderer'),
              FilledButton(
                  onPressed: () => setState(() => selected = !selected),
                  child: Text(
                      selected ? 'Clear console selection' : 'Select SNES')),
              FilledButton(
                  onPressed: () => ref
                      .read(mediaPresentationProvider.notifier)
                      .toggleMotion(),
                  child: Text(ref.watch(mediaPresentationProvider).reducedMotion
                      ? 'Enable rotation'
                      : 'Reduce motion')),
            ],
          )))));
}
