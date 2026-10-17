import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/preview_settings.dart';
import '../services/secondary_preview.dart';
import '../services/storage_service.dart';
import 'app_providers.dart';

class PreviewSettingsNotifier extends StateNotifier<PreviewSettings> {
  final StorageService storage;
  Future<void> _write = Future.value();
  PreviewSettingsNotifier(this.storage) : super(storage.getPreviewSettings());
  Future<void> change(String key, Object value) {
    final next = state.change(key, value);
    state = next;
    return _write = _write
        .catchError((Object _) {})
        .then((_) => storage.setPreviewSettings(next));
  }
}

final previewSettingsProvider =
    StateNotifierProvider<PreviewSettingsNotifier, PreviewSettings>(
        (ref) => PreviewSettingsNotifier(ref.watch(storageServiceProvider)));
final secondaryPreviewProvider =
    ChangeNotifierProvider<SecondaryPreview>((ref) {
  final bridge = SecondaryPreview(
      onPlaybackChanged: ref.read(audioManagerProvider).setPreviewPlaying);
  void prepare() {
    if (!Platform.isAndroid) return;
    final resources = ref.read(socketMediaImportProvider);
    unawaited(bridge.prepare(
        enabled: ref.read(previewSettingsProvider).enabled,
        resourceRoot: resources.rootDirectory?.path,
        resourceGeneration: resources.generation));
  }

  ref.listen(previewSettingsProvider.select((settings) => settings.enabled),
      (_, __) => prepare());
  ref.listen(
      socketMediaImportProvider.select((resources) => resources.generation),
      (_, __) => prepare());
  prepare();
  return bridge;
});
final dualScreenPreviewProvider = Provider<bool>((ref) =>
    ref.watch(previewSettingsProvider).enabled &&
    ref.watch(secondaryPreviewProvider).available);
