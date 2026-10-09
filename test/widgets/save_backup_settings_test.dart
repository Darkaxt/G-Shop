import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:retro_eshop/features/settings/save_backup_settings_screen.dart';
import 'package:retro_eshop/models/config/app_config.dart';
import 'package:retro_eshop/models/config/source.dart';
import 'package:retro_eshop/models/config/drive_source_config.dart';
import 'package:retro_eshop/providers/app_providers.dart';
import 'package:retro_eshop/services/config_storage_service.dart';
import 'package:retro_eshop/services/sources_notifier.dart';
import 'package:retro_eshop/services/drive/drive_authorization.dart';
import 'package:retro_eshop/services/saves/drive_save_backup_area.dart';
import 'package:retro_eshop/services/saves/save_backup_setup.dart';
import '../helpers/pump_helpers.dart';

class _Driver implements DriveAuthorizationDriver {
  final started = Completer<void>();
  final consent = Completer<String?>();
  @override
  Future<String?> authenticate({required bool interactive}) async => 'account';
  @override
  Future<String?> authorize(String accountId, List<String> scopes,
      {required bool interactive}) async {
    if (interactive) {
      if (!started.isCompleted) started.complete();
      return consent.future;
    }
    return 'token';
  }

  @override
  Future<void> clearRejectedToken(String accountId, String token) async {}
  @override
  Future<void> signOut({required bool revoke}) async {}
}

class _Transport implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(RequestOptions request, Stream<Uint8List>? data,
      Future<void>? cancelFuture) async {
    requests.add(request);
    return ResponseBody.fromString(
        jsonEncode({
          'files': [
            {
              'id': 'area',
              'mimeType': 'application/vnd.google-apps.folder',
              'ownedByMe': true,
              'isAppAuthorized': true,
              'trashed': false,
              'shared': false,
              'appProperties': {'rshopSaveBackup': '1', 'kind': 'area'}
            }
          ],
          'incompleteSearch': false
        }),
        200);
  }

  @override
  void close({bool force = false}) {}
}

class _ConfigStorage extends ConfigStorageService {
  @override
  Future<AppConfig?> loadConfig() async => AppConfig.empty;
}

class _Sources extends SourcesNotifier {
  _Sources() : super(_ConfigStorage());
  void publish(String? account) {
    state = SourcesState(sources: [
      if (account != null)
        Source(
            id: 'same-source',
            name: 'Drive',
            type: SourceType.drive,
            drive: DriveSourceConfig(
                accountId: account,
                rootFolderId: 'root-id',
                serverClientId: 'settings-test-client')),
    ]);
  }
}

void main() {
  testWidgets('same source account change retires the old backup setup',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      SaveBackupSetup.storageKey('settings-test-client', 'first-account'):
          jsonEncode({'areaId': 'first-area', 'ready': true}),
    });
    final sources = _Sources();
    await sources.ready;
    sources.publish('first-account');
    await tester.pumpWidget(ProviderScope(overrides: [
      sourcesProvider.overrideWith((_) => sources),
    ], child: createTestApp(const SaveBackupSettingsScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Private backup area prepared'), findsOneWidget);
    sources.publish('second-account');
    await tester.pumpAndSettle();
    expect(find.text('Private backup area prepared'), findsNothing);
    expect(find.byKey(const ValueKey('save-backup-authorize')), findsOneWidget);
    final panel =
        tester.widget<SaveBackupSetupPanel>(find.byType(SaveBackupSetupPanel));
    expect(panel.setup.accountId, 'second-account');
    expect(panel.setup.areaId, isNull);
    sources.publish(null);
    await tester.pumpAndSettle();
    expect(find.byType(SaveBackupSetupPanel), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'setup explains its boundary and remains touch/controller reachable',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final driver = _Driver();
    final authorization = DriveAuthorization(driver);
    final transport = _Transport();
    final setup = SaveBackupSetup(
        accountId: 'account',
        clientId: 'client',
        preferences: prefs,
        authorization: authorization,
        api: DriveSaveBackupAreaApi(
            authorization: authorization,
            accountId: 'account',
            transport: transport));
    addTearDown(setup.dispose);
    await setup.load();
    await tester.pumpWidget(ProviderScope(
        child: createTestApp(SaveBackupSetupPanel(setup: setup))));
    await tester.pumpAndSettle();
    expect(find.textContaining('ROM sources remain read-only'), findsOneWidget);
    expect(find.textContaining('No save groups mapped yet'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('save-backup-authorize')));
    await tester.pump();
    await driver.started.future;
    expect(setup.busy, isTrue);
    expect(find.byKey(const ValueKey('save-backup-cancel')), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('save-backup-authorize')))
            .onPressed,
        isNull);
    await tester.tap(find.byKey(const ValueKey('save-backup-cancel')));
    driver.consent.complete('token');
    await tester.pumpAndSettle();
    expect(setup.ready, isFalse);
    expect(transport.requests, isEmpty);
    final authorize = find.byKey(const ValueKey('save-backup-authorize'));
    final context = tester.element(authorize);
    Focus.of(context).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(transport.requests, hasLength(2));
    expect(transport.requests.last.uri.path, endsWith('/files/area'));
    expect(setup.issue, isNotNull); // Synthetic response fails exact root GET.
    expect(find.textContaining('Setup needs attention:'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
