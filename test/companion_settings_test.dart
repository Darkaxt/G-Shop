import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:retro_eshop/services/storage_service.dart';

class _RejectCompanionWrite extends InMemorySharedPreferencesStore {
  _RejectCompanionWrite() : super.empty();
  @override
  Future<bool> setValue(String type, String key, Object value) async => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late StorageService storage;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    storage = StorageService();
    await storage.init();
  });

  test('two edition associations survive restart independently', () async {
    await storage.setCompanion(
        'edition-one', 'com.example.reader/.MainActivity');
    await storage.setCompanion(
        'edition-two', 'com.example.notes/.NotesActivity');
    final restored = StorageService();
    await restored.init();
    expect(restored.getCompanion('edition-one'),
        'com.example.reader/.MainActivity');
    expect(restored.getCompanion('edition-two'),
        'com.example.notes/.NotesActivity');
    expect(restored.getCompanion('different-edition'), isNull);
  });

  test(
      'change and clear affect only the selected edition and preserve favorites',
      () async {
    await storage.setCompanion(
        'edition-one', 'com.example.reader/.MainActivity');
    await storage.setCompanion(
        'edition-two', 'com.example.notes/.NotesActivity');
    await storage.toggleFavorite('artifact-one');
    await storage.setCompanion('edition-one', 'com.example.other/.Main');
    expect(storage.getCompanion('edition-one'), 'com.example.other/.Main');
    await storage.setCompanion('edition-one', null);
    expect(storage.getCompanion('edition-one'), isNull);
    expect(storage.getCompanion('edition-two'),
        'com.example.notes/.NotesActivity');
    expect(storage.getFavorites(), ['artifact-one']);
  });

  test('concurrent independent selections are serialized without lost writes',
      () async {
    await Future.wait<void>([
      storage.setCompanion('edition-one', 'com.example.reader/.MainActivity'),
      storage.setCompanion('edition-two', 'com.example.notes/.NotesActivity'),
      storage.toggleFavorite('artifact-one'),
    ]);
    expect(storage.getCompanion('edition-one'), isNotNull);
    expect(storage.getCompanion('edition-two'), isNotNull);
    expect(storage.getFavorites(), ['artifact-one']);
  });

  test('rejected durable write never presents a saved companion', () async {
    final original = SharedPreferencesStorePlatform.instance;
    addTearDown(() => SharedPreferencesStorePlatform.instance = original);
    SharedPreferencesStorePlatform.instance = _RejectCompanionWrite();
    await expectLater(
        storage.setCompanion('edition-one', 'com.example.reader/.MainActivity'),
        throwsStateError);
    expect(storage.getCompanion('edition-one'), isNull);
  });

  test('empty identity and non-component targets are rejected', () async {
    await expectLater(
        Future<void>.sync(
            () => storage.setCompanion('', 'com.example.reader/.MainActivity')),
        throwsArgumentError);
    await expectLater(
        Future<void>.sync(
            () => storage.setCompanion('edition-one', 'file:///some.apk')),
        throwsArgumentError);
  });
}
