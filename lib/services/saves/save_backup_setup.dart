import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../drive/drive_authorization.dart';
import 'drive_save_backup_area.dart';

class SaveBackupSetup extends ChangeNotifier {
  final String accountId, clientId;
  final SharedPreferences _preferences;
  final DriveAuthorization _authorization;
  final DriveSaveBackupAreaApi _api;
  bool _ready = false, _loaded = false, _disposed = false;
  String? _areaId, _issue;
  Future<void>? _operation;
  CancelToken? _cancellation;

  SaveBackupSetup(
      {required this.accountId,
      required this.clientId,
      required SharedPreferences preferences,
      required DriveAuthorization authorization,
      required DriveSaveBackupAreaApi api})
      : _preferences = preferences,
        _authorization = authorization,
        _api = api {
    if (accountId.trim().isEmpty ||
        clientId.trim().isEmpty ||
        api.accountId != accountId) {
      throw ArgumentError('Invalid backup binding');
    }
  }

  static String storageKey(String clientId, String accountId) =>
      'rshop_save_backup_area_v1:${Uri.encodeComponent(jsonEncode([
            clientId,
            accountId
          ]))}';
  String get _key => storageKey(clientId, accountId);
  bool get ready => _ready;
  bool get busy => _operation != null;
  String? get areaId => _areaId;
  String? get issue => _issue;

  /// Local readiness is a remembered setup, NOT current cloud authorization or
  /// a successful save backup. Every backup/restore must revalidate its area.
  Future<void> load() async {
    if (_loaded || _disposed) return;
    final saved = _preferences.getString(_key);
    try {
      if (saved != null) {
        final data = jsonDecode(saved);
        if (data is! Map ||
            data.length != 2 ||
            data['areaId'] is! String ||
            !RegExp(r'^[A-Za-z0-9_-]{1,256}$')
                .hasMatch(data['areaId'] as String) ||
            data['ready'] is! bool) {
          throw const FormatException();
        }
        _areaId = data['areaId'] as String;
        _ready = data['ready'] as bool;
      }
    } catch (_) {
      // Do not overwrite an unreadable recovery intent with a new remote area.
      _issue = 'savedSetupInvalid';
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist({required bool ready}) async {
    if (!await _preferences.setString(
        _key, jsonEncode({'areaId': _areaId, 'ready': ready}))) {
      throw StateError('Backup setup was not persisted');
    }
  }

  void _check(CancelToken cancellation) {
    if (_disposed || cancellation.isCancelled) {
      throw const SaveBackupAreaException(SaveBackupAreaIssue.cancelled);
    }
  }

  Future<void> prepare() {
    if (_disposed) return Future.value();
    final pending = _operation;
    if (pending != null) return pending;
    final cancellation = CancelToken();
    _cancellation = cancellation;
    // Reserve the operation synchronously; no second activation can enter setup
    // while load/consent/storage/network work is awaiting.
    final operation = Future<void>.microtask(() async {
      try {
        await load();
        _check(cancellation);
        if (_issue == 'savedSetupInvalid') return;
        _issue = null;
        await _authorization.requestBackupConsent(expectedAccountId: accountId);
        _check(cancellation);
        final id = _areaId;
        if (id == null) {
          final areas = await _api.discover(cancellation: cancellation);
          _check(cancellation);
          if (areas.length > 1) {
            _issue = 'ambiguousAreas';
            return;
          }
          _areaId = areas.isEmpty
              ? await _api.reserveAreaId(cancellation: cancellation)
              : areas.single.id;
          _check(cancellation);
        }
        // A failed preference write still updates its optimistic memory cache.
        // A retry (including a new controller in this process) must acknowledge
        // the recovery identity again before any possible remote creation.
        await _persist(ready: _ready);
        _check(cancellation);
        final area =
            await _api.createReservedArea(_areaId!, cancellation: cancellation);
        _check(cancellation);
        if (area.accountId != accountId || area.id != _areaId) {
          throw const SaveBackupAreaException(SaveBackupAreaIssue.unownedArea);
        }
        await _persist(ready: true);
        _check(cancellation);
        _ready = true;
      } on DriveAuthorizationException catch (error) {
        _issue = 'authorization_${error.issue.name}';
      } on SaveBackupAreaException catch (error) {
        _issue = error.issue.name;
      } catch (_) {
        _issue = 'setupUnavailable';
      } finally {
        _operation = null;
        _cancellation = null;
        if (!_disposed) notifyListeners();
      }
    });
    _operation = operation;
    notifyListeners();
    return operation;
  }

  void cancel() => _cancellation?.cancel();

  Future<void> cancelAndJoin() async {
    cancel();
    await _operation;
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
    // Do not close the native transport out from under an active operation.
    final pending = _operation;
    if (pending == null) {
      _api.close();
    } else {
      pending.whenComplete(_api.close);
    }
    super.dispose();
  }
}
