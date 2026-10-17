import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/commercial_release_preference.dart';
import '../services/storage_service.dart';
import 'app_providers.dart';

class CollectionPreferencesNotifier
    extends StateNotifier<CommercialReleasePreference> {
  final StorageService storage;
  Future<void> _write = Future.value();
  CollectionPreferencesNotifier(this.storage)
      : super(storage.getCommercialReleasePreference());

  Future<void> change(CommercialReleasePreference next) {
    return _write = _write.catchError((Object _) {}).then((_) async {
      await storage.setCommercialReleasePreference(next);
      if (mounted) state = next;
    });
  }
}

final collectionPreferencesProvider = StateNotifierProvider<
        CollectionPreferencesNotifier, CommercialReleasePreference>(
    (ref) => CollectionPreferencesNotifier(ref.watch(storageServiceProvider)));
