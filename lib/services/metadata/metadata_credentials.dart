import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class MetadataSecretStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterMetadataSecretStorage implements MetadataSecretStorage {
  final FlutterSecureStorage _storage;
  FlutterMetadataSecretStorage({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              // Startup's StorageService migrates this same namespace to
              // encrypted preferences. Mixing Android modes makes subsequent
              // default-mode reads return null after that migration.
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );
  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class ScreenScraperDeveloperCredentials {
  final String developerId;
  final String developerPassword;
  final String softwareName;
  const ScreenScraperDeveloperCredentials(
      {required this.developerId,
      required this.developerPassword,
      required this.softwareName});
  bool get isConfigured =>
      developerId.trim().isNotEmpty &&
      developerPassword.trim().isNotEmpty &&
      softwareName.trim().isNotEmpty;
  @override
  String toString() => 'ScreenScraperDeveloperCredentials(redacted)';
}

class ScreenScraperUserCredentials {
  final String username;
  final String password;
  const ScreenScraperUserCredentials(
      {required this.username, required this.password});
  bool get isConfigured =>
      username.trim().isNotEmpty && password.trim().isNotEmpty;
  @override
  String toString() => 'ScreenScraperUserCredentials(redacted)';
}

class MetadataCredentialStorageException implements Exception {
  const MetadataCredentialStorageException();
  @override
  String toString() => 'Metadata credentials could not be accessed securely.';
}

/// Private application configuration, never exported into catalogue or config JSON.
class IgdbCredentials {
  final String clientId;
  final String clientSecret;
  const IgdbCredentials(this.clientId, this.clientSecret);
  bool get isConfigured =>
      clientId.trim().isNotEmpty && clientSecret.trim().isNotEmpty;
  @override
  String toString() => 'IgdbCredentials(redacted)';
}

class IgdbCredentialStore {
  final MetadataSecretStorage _storage;
  Future<void> _tail = Future.value();
  static const _id = 'rshop.metadata.igdb.client.id';
  static const _secret = 'rshop.metadata.igdb.client.secret';
  IgdbCredentialStore({MetadataSecretStorage? storage})
      : _storage = storage ?? FlutterMetadataSecretStorage();

  Future<T> _serial<T>(Future<T> Function() operation) {
    final before = _tail;
    final done = Completer<void>();
    _tail = done.future;
    return () async {
      await before;
      try {
        return await operation();
      } catch (_) {
        throw const MetadataCredentialStorageException();
      } finally {
        done.complete();
      }
    }();
  }

  Future<IgdbCredentials?> read() => _serial(() async {
        final id = await _storage.read(_id);
        final secret = await _storage.read(_secret);
        if (id == null || secret == null) return null;
        final credentials = IgdbCredentials(id, secret);
        return credentials.isConfigured ? credentials : null;
      });

  Future<void> save(IgdbCredentials credentials) {
    if (!credentials.isConfigured) {
      throw ArgumentError('Incomplete application access');
    }
    return _serial(() async {
      await _storage.delete(_id);
      await _storage.write(_secret, credentials.clientSecret);
      await _storage.write(_id, credentials.clientId);
    });
  }

  Future<void> remove() => _serial(() async {
        await _storage.delete(_id);
        await _storage.delete(_secret);
      });
}

/// Separate application authorization and account credentials. Neither type has
/// an export/config JSON representation. Secure storage is the only persistence.
/// Store instances should be shared by their provider setup and lookup callers.
class ScreenScraperCredentialStore {
  final MetadataSecretStorage _storage;
  Future<void> _tail = Future.value();
  static const _developerId = 'rshop.metadata.screenscraper.developer.id';
  static const _developerPassword =
      'rshop.metadata.screenscraper.developer.password';
  static const _softwareName =
      'rshop.metadata.screenscraper.developer.software';
  static const _username = 'rshop.metadata.screenscraper.user.name';
  static const _password = 'rshop.metadata.screenscraper.user.password';

  ScreenScraperCredentialStore({MetadataSecretStorage? storage})
      : _storage = storage ?? FlutterMetadataSecretStorage();

  Future<T> _serial<T>(Future<T> Function() operation) {
    final before = _tail;
    final done = Completer<void>();
    _tail = done.future;
    return () async {
      await before;
      try {
        return await operation();
      } catch (_) {
        throw const MetadataCredentialStorageException();
      } finally {
        done.complete();
      }
    }();
  }

  Future<ScreenScraperDeveloperCredentials?> readDeveloper() =>
      _serial(() async {
        final id = await _storage.read(_developerId);
        final password = await _storage.read(_developerPassword);
        final software = await _storage.read(_softwareName);
        if (id == null || password == null || software == null) {
          return null;
        }
        final credentials = ScreenScraperDeveloperCredentials(
            developerId: id,
            developerPassword: password,
            softwareName: software);
        return credentials.isConfigured ? credentials : null;
      });

  Future<ScreenScraperUserCredentials?> readUser() => _serial(() async {
        final username = await _storage.read(_username);
        final password = await _storage.read(_password);
        if (username == null || password == null) {
          return null;
        }
        final credentials = ScreenScraperUserCredentials(
            username: username, password: password);
        return credentials.isConfigured ? credentials : null;
      });

  Future<void> saveDeveloper(ScreenScraperDeveloperCredentials credentials) {
    if (!credentials.isConfigured) {
      throw ArgumentError('Developer configuration is incomplete.');
    }
    return _serial(() async {
      // ID is the commit marker; an interrupted write cannot look configured.
      await _storage.delete(_developerId);
      await _storage.write(_developerPassword, credentials.developerPassword);
      await _storage.write(_softwareName, credentials.softwareName);
      await _storage.write(_developerId, credentials.developerId);
    });
  }

  Future<void> saveUser(ScreenScraperUserCredentials credentials) {
    if (!credentials.isConfigured) {
      throw ArgumentError('Account credentials are incomplete.');
    }
    return _serial(() async {
      await _storage.delete(_username);
      await _storage.write(_password, credentials.password);
      await _storage.write(_username, credentials.username);
    });
  }

  Future<void> removeUser() => _serial(() async {
        await _storage.delete(_username);
        await _storage.delete(_password);
      });

  Future<void> removeDeveloper() => _serial(() async {
        await _storage.delete(_developerId);
        await _storage.delete(_developerPassword);
        await _storage.delete(_softwareName);
      });
}
