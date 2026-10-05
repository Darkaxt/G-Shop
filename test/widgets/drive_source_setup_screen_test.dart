import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/features/sources/drive_source_setup_screen.dart';
import 'package:retro_eshop/models/config/source.dart';
import 'package:retro_eshop/models/config/drive_source_config.dart';
import 'package:retro_eshop/services/drive/drive_api.dart';

class _FakeApi implements DriveCatalogueApi {
  @override
  Future<DriveFile> getFile(String id, {cancelToken}) async {
    expect(id, 'root');
    return DriveFile(
      id: 'actual-root-id',
      name: 'My Drive',
      mimeType: DriveFile.folderMime,
      parents: const [],
    );
  }

  @override
  Future<DriveFilePage> listChildren(
    String parentId, {
    String? pageToken,
    bool foldersOnly = false,
    cancelToken,
  }) async {
    expect(foldersOnly, isTrue);
    if (parentId == 'console-folder-id') {
      return DriveFilePage(files: const []);
    }
    expect(parentId, 'actual-root-id');
    return DriveFilePage(files: [
      DriveFile(
        id: 'console-folder-id',
        name: 'SNES',
        mimeType: DriveFile.folderMime,
        parents: const ['actual-root-id'],
      ),
      DriveFile(
        id: 'shortcut-id',
        name: 'Outside shortcut',
        mimeType: 'application/vnd.google-apps.shortcut',
        parents: const ['actual-root-id'],
      ),
    ]);
  }
}

class _FakeConnector implements DriveSourceSetupConnector {
  String? receivedClientId;

  @override
  Future<DriveSourceConnection> connect(String serverClientId) async {
    receivedClientId = serverClientId;
    return DriveSourceConnection(accountId: 'account-id', api: _FakeApi());
  }
}

class _RepeatingPageApi extends _FakeApi {
  @override
  Future<DriveFilePage> listChildren(
    String parentId, {
    String? pageToken,
    bool foldersOnly = false,
    cancelToken,
  }) async {
    return DriveFilePage(files: const [], nextPageToken: 'repeated');
  }
}

class _RepeatingConnector implements DriveSourceSetupConnector {
  @override
  Future<DriveSourceConnection> connect(String serverClientId) async =>
      DriveSourceConnection(accountId: 'account-id', api: _RepeatingPageApi());
}

void main() {
  testWidgets('configured source requests connection, not OAuth setup',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
          home: DriveSourceSetupScreen(
        initialSource: const Source(
          id: 'existing-source',
          name: 'Cloud ROMs',
          type: SourceType.drive,
          drive: DriveSourceConfig(
              accountId: 'account-id',
              rootFolderId: 'console-folder-id',
              serverClientId: 'public-client.apps.googleusercontent.com'),
        ),
        connector: _FakeConnector(),
        onSave: (_) async {},
      )),
    ));
    expect(find.text('Connect to Google Drive'), findsOneWidget);
    expect(find.text('Setup required'), findsNothing);
    expect(
        find.textContaining('Create a public Web OAuth client'), findsNothing);
    await tester.tap(find.text('Connect'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Connected to Google Drive'), findsOneWidget);
    expect(find.text('Connect to Google Drive'), findsNothing);
  });

  testWidgets('opening a folder resets the parent scroll position',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
          home: DriveSourceSetupScreen(
        connector: _FakeConnector(),
        onSave: (_) async {},
      )),
    ));
    await tester.enterText(find.byKey(const Key('drive_server_client_id')),
        'public-client.apps.googleusercontent.com');
    await tester.tap(find.text('Connect'));
    await tester.pump();
    await tester.pump();
    final folderList = find.byWidgetPredicate((widget) =>
        widget is Scrollable && widget.axisDirection == AxisDirection.down);
    await tester.scrollUntilVisible(find.text('SNES'), 160,
        scrollable: folderList);
    expect(tester.state<ScrollableState>(folderList).position.pixels,
        greaterThan(0));
    await tester.tap(find.text('SNES'));
    await tester.pump();
    await tester.pump();
    expect(tester.state<ScrollableState>(folderList).position.pixels, 0);
    await tester.scrollUntilVisible(find.text('Use this folder'), 80,
        scrollable: folderList);
    await tester.tap(find.text('Use this folder'));
    await tester.pump();
    expect(find.text('Selected: SNES'), findsOneWidget);
  });

  testWidgets('connects, exposes unsupported entries, and saves actual root ID',
      (tester) async {
    final connector = _FakeConnector();
    Source? saved;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: DriveSourceSetupScreen(
            connector: connector,
            onSave: (source) async => saved = source,
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('drive_source_name')),
      'Cloud ROMs',
    );
    await tester.enterText(
      find.byKey(const Key('drive_server_client_id')),
      'public-client.apps.googleusercontent.com',
    );
    await tester.tap(find.text('Connect'));
    await tester.pump();
    await tester.pump();

    expect(
      connector.receivedClientId,
      'public-client.apps.googleusercontent.com',
    );
    expect(find.text('My Drive'), findsWidgets);
    expect(find.text('Connected to Google Drive'), findsOneWidget);
    expect(find.text('Setup required'), findsNothing);
    final folderList = find.byWidgetPredicate((widget) =>
        widget is Scrollable && widget.axisDirection == AxisDirection.down);
    await tester.scrollUntilVisible(
      find.text('SNES'),
      160,
      scrollable: folderList,
    );
    expect(find.text('SNES'), findsOneWidget);
    expect(find.textContaining('Outside shortcut'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Use this folder'),
      -160,
      scrollable: folderList,
    );
    await tester.tap(find.text('Use this folder'));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Save source'),
      160,
      scrollable: folderList,
    );
    await tester.tap(find.text('Save source'));
    await tester.pump();

    expect(saved?.type, SourceType.drive);
    expect(saved?.auth, isNull);
    expect(saved?.drive?.accountId, 'account-id');
    expect(saved?.drive?.rootFolderId, 'actual-root-id');
    expect(
      saved?.drive?.serverClientId,
      'public-client.apps.googleusercontent.com',
    );
  });

  testWidgets(
      'does not offer a successful save before connection and selection',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: DriveSourceSetupScreen(
            connector: _FakeConnector(),
            onSave: (_) async {},
          ),
        ),
      ),
    );

    expect(find.text('Setup required'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save source'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('repeated page tokens fail closed instead of spinning',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: DriveSourceSetupScreen(
            connector: _RepeatingConnector(),
            onSave: (_) async {},
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('drive_server_client_id')),
      'public-client.apps.googleusercontent.com',
    );
    await tester.tap(find.text('Connect'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Google Drive: invalidPageToken'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
