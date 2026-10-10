import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/database_service.dart';
import '../services/saves/automatic_save_backups.dart';
import '../services/saves/save_background_dispatch.dart';
import 'app_providers.dart';

/// Application owned: leaving Settings must not cancel an enabled return check.
final automaticSaveBackupsProvider =
    FutureProvider<AutomaticSaveBackups>((ref) async {
  // Startup configuration and SourcesNotifier load independently. An empty
  // initial snapshot is not evidence that the saved source was removed.
  await ref.read(sourcesProvider.notifier).ready;
  final preferences = await SharedPreferences.getInstance();
  final service = AutomaticSaveBackups(
      database: DatabaseService().database,
      preferences: preferences,
      refreshConfiguration: preferences.reload,
      scheduleBackground: SaveBackgroundDispatch.schedule,
      sources: () => ref.read(sourcesProvider).sources);
  ref.onDispose(service.dispose);
  await SaveBackgroundDispatch.bind(service);
  return service;
});
