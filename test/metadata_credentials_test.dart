import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/services/metadata/metadata_credentials.dart';

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
  test('account removal preserves independent developer authorization',
      () async {
    final storage = _MemorySecrets();
    final credentials = ScreenScraperCredentialStore(storage: storage);
    await credentials.saveDeveloper(const ScreenScraperDeveloperCredentials(
      developerId: 'fixture-dev',
      developerPassword: 'fixture-dev-secret',
      softwareName: 'R-Shop-fixture',
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
    expect((await credentials.readDeveloper())!.softwareName, 'R-Shop-fixture');
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
