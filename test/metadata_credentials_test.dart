import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/services/metadata/metadata_credentials.dart';

class _MemorySecrets implements MetadataSecretStorage {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('IGDB private application pair is secure and independently removable',
      () async {
    final storage = _MemorySecrets();
    final store = IgdbCredentialStore(storage: storage);
    expect(await store.read(), isNull);
    await store.save(const IgdbCredentials('fixture-id', 'fixture-secret'));
    expect((await store.read())!.clientId, 'fixture-id');
    expect((await store.read())!.clientSecret, 'fixture-secret');
    expect('${await store.read()}', isNot(contains('secret')));
    await store.remove();
    expect(await store.read(), isNull);
    expect(() => store.save(const IgdbCredentials('', 'fixture')),
        throwsArgumentError);
  });
  test('account removal preserves independent developer authorization',
      () async {
    final storage = _MemorySecrets();
    final credentials = ScreenScraperCredentialStore(storage: storage);
    await credentials.saveDeveloper(const ScreenScraperDeveloperCredentials(
      developerId: 'fixture-dev',
      developerPassword: 'fixture-dev-secret',
      softwareName: 'G-Shop-fixture',
    ));
    await credentials.saveUser(const ScreenScraperUserCredentials(
      username: 'fixture-user',
      password: 'fixture-user-secret',
    ));
    expect((await credentials.readDeveloper())!.developerId, 'fixture-dev');
    expect((await credentials.readUser())!.username, 'fixture-user');
    expect(
        storage.values.values.any((value) => value.startsWith('{')), isFalse);
    await credentials.removeUser();
    expect(await credentials.readUser(), isNull);
    expect((await credentials.readDeveloper())!.softwareName, 'G-Shop-fixture');
    expect('${await credentials.readDeveloper()}', isNot(contains('secret')));
  });

  test('empty credentials cannot be stored as configured access', () async {
    final store = ScreenScraperCredentialStore(storage: _MemorySecrets());
    expect(
        () => store.saveUser(const ScreenScraperUserCredentials(
              username: '',
              password: 'fixture',
            )),
        throwsArgumentError);
  });

  test('Flutter secure storage adapter reads, writes and deletes exact keys',
      () async {
    FlutterSecureStorage.setMockInitialValues({});
    final storage = FlutterMetadataSecretStorage();
    await storage.write('metadata-fixture', 'fixture-secret');
    expect(await storage.read('metadata-fixture'), 'fixture-secret');
    await storage.delete('metadata-fixture');
    expect(await storage.read('metadata-fixture'), isNull);
  });
}
