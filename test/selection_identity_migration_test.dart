import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:retro_eshop/providers/app_providers.dart';
import 'package:retro_eshop/models/game_item.dart';
import 'package:retro_eshop/models/custom_shelf.dart';
import 'package:retro_eshop/services/storage_service.dart';

class _RejectSelectionWrite extends InMemorySharedPreferencesStore {
  _RejectSelectionWrite() : super.empty();
  bool reject = false;
  bool rejectVersion = false;
  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (reject && key.endsWith('exact_selections_v1')) return false;
    if (rejectVersion && key.endsWith('favorites_version')) return false;
    return super.setValue(valueType, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late StorageService storage;
  setUp(() async {
    SharedPreferences.setMockInitialValues({'secure_auth_migrated': true});
    FlutterSecureStorage.setMockInitialValues({});
    storage = StorageService();
    await storage.init();
    await storage.setFavorites(['Old.7z']);
    await storage.setCustomShelves([
      CustomShelf(
          id: 'shelf',
          name: 'Shelf',
          createdAt: DateTime.utc(2026),
          sortMode: ShelfSortMode.manual,
          manualGameIds: ['Before', 'Old.7z', 'After'],
          excludedGameIds: ['Old.7z'])
    ]);
  });
  test(
      'one durable selection update retains ordering, exclusions and unfavorite after restart',
      () async {
    await storage.migrateExactSelections({
      'psx': {'Old.7z': 'artifact:psx'}
    }, remainingLegacyKeys: {});
    expect(storage.getFavorites(), ['artifact:psx']);
    expect(storage.getCustomShelves().single.manualGameIds,
        ['Before', 'artifact:psx', 'After']);
    expect(storage.getCustomShelves().single.excludedGameIds, ['artifact:psx']);
    await storage.toggleFavorite('artifact:psx');
    final restored = StorageService();
    await restored.init();
    await restored.migrateExactSelections({
      'psx': {'Old.7z': 'artifact:psx'}
    }, remainingLegacyKeys: {});
    expect(restored.getFavorites(), isEmpty);
  });
  test(
      'another console namesake keeps its selection without refavoriting an exact game',
      () async {
    await storage.migrateExactSelections({
      'psx': {'Old.7z': 'artifact:psx'}
    }, remainingLegacyKeys: {
      'Old.7z'
    });
    expect(storage.getFavorites().toSet(), {'Old.7z', 'artifact:psx'});
    await storage.toggleFavorite('artifact:psx');
    await storage.migrateExactSelections({
      'psx': {'Old.7z': 'artifact:psx'},
      'ps2': {'Old.7z': 'artifact:ps2'}
    }, remainingLegacyKeys: {});
    expect(storage.getFavorites(), ['artifact:ps2']);
  });
  test('a concurrent toggle is sequenced after identity migration', () async {
    final migration = storage.migrateExactSelections({
      'psx': {'Old.7z': 'artifact:psx'}
    }, remainingLegacyKeys: {});
    final toggle = storage.toggleFavorite('artifact:psx');
    await migration;
    await toggle;
    expect(storage.getFavorites(), isEmpty);
  });
  test(
      'rejected persistence restores durable selections and can retry without a false receipt',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final store = _RejectSelectionWrite();
    await store.setValue('String', 'flutter.exact_selections_v1',
        prefs.getString('exact_selections_v1')!);
    final previous = SharedPreferencesStorePlatform.instance;
    addTearDown(() => SharedPreferencesStorePlatform.instance = previous);
    SharedPreferencesStorePlatform.instance = store;
    store.reject = true;
    await expectLater(
        storage.migrateExactSelections({
          'psx': {'Old.7z': 'artifact:psx'}
        }, remainingLegacyKeys: {}),
        throwsStateError);
    expect(storage.getFavorites(), ['Old.7z']);
    expect(storage.getCustomShelves().single.manualGameIds,
        ['Before', 'Old.7z', 'After']);
    store.reject = false;
    await storage.migrateExactSelections({
      'psx': {'Old.7z': 'artifact:psx'}
    }, remainingLegacyKeys: {});
    expect(storage.getFavorites(), ['artifact:psx']);
  });
  test(
      'a fresh profile records filename semantics and retains unresolved selections',
      () async {
    await storage.setFavorites([]);
    final notifier = FavoriteGamesNotifier(storage);
    addTearDown(notifier.dispose);
    await notifier.migrateIfNeeded([]);
    expect(storage.getFavoritesVersion(), 1);
    await notifier.toggleFavorite('artifact:exact');
    final restored = FavoriteGamesNotifier(storage);
    addTearDown(restored.dispose);
    await restored.migrateIfNeeded(
        [const GameItem(filename: 'Other', displayName: 'Other', url: '')]);
    expect(restored.state, ['artifact:exact']);
  });
  test('legacy favorite migration can retry after rejected persistence',
      () async {
    await storage.setFavorites(['Legacy Title']);
    final notifier = FavoriteGamesNotifier(storage);
    addTearDown(notifier.dispose);
    const games = [
      GameItem(filename: 'Legacy.7z', displayName: 'Legacy Title', url: '')
    ];
    final prefs = await SharedPreferences.getInstance();
    final store = _RejectSelectionWrite();
    await store.setValue('String', 'flutter.exact_selections_v1',
        prefs.getString('exact_selections_v1')!);
    final previous = SharedPreferencesStorePlatform.instance;
    addTearDown(() => SharedPreferencesStorePlatform.instance = previous);
    SharedPreferencesStorePlatform.instance = store;

    store.reject = true;
    await expectLater(notifier.migrateIfNeeded(games), throwsStateError);
    expect(notifier.state, ['Legacy Title']);
    expect(storage.getFavorites(), ['Legacy Title']);
    expect(storage.getFavoritesVersion(), 0);

    store.reject = false;
    await notifier.migrateIfNeeded(games);
    expect(notifier.state, ['Legacy.7z']);
    expect(storage.getFavorites(), ['Legacy.7z']);
    expect(storage.getFavoritesVersion(), 1);
    final restored = StorageService();
    await restored.init();
    final restoredNotifier = FavoriteGamesNotifier(restored);
    addTearDown(restoredNotifier.dispose);
    expect(restoredNotifier.state, ['Legacy.7z']);
  });
  test('legacy migration requires a durable version acknowledgment', () async {
    await storage.setFavorites(['Legacy Title']);
    final notifier = FavoriteGamesNotifier(storage);
    addTearDown(notifier.dispose);
    const games = [
      GameItem(filename: 'Legacy.7z', displayName: 'Legacy Title', url: '')
    ];
    final prefs = await SharedPreferences.getInstance();
    final store = _RejectSelectionWrite();
    await store.setValue('String', 'flutter.exact_selections_v1',
        prefs.getString('exact_selections_v1')!);
    final previous = SharedPreferencesStorePlatform.instance;
    addTearDown(() => SharedPreferencesStorePlatform.instance = previous);
    SharedPreferencesStorePlatform.instance = store;

    store.rejectVersion = true;
    await expectLater(notifier.migrateIfNeeded(games), throwsStateError);
    expect(storage.getFavoritesVersion(), 0);
    expect(notifier.state, ['Legacy Title']);
    // The first selection write may have committed before the version failed.
    // Retrying the original migration must remain idempotent and retain it.
    expect(storage.getFavorites(), ['Legacy.7z']);
    store.rejectVersion = false;
    await notifier.migrateIfNeeded(games);
    expect(storage.getFavoritesVersion(), 1);
    expect(notifier.state, ['Legacy.7z']);
    final restored = StorageService();
    await restored.init();
    expect(restored.getFavoritesVersion(), 1);
    expect(restored.getFavorites(), ['Legacy.7z']);
  });
}
