import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/features/sources/drive_source_mappings_screen.dart';
import 'package:retro_eshop/models/config/app_config.dart';
import 'package:retro_eshop/models/config/source.dart';
import 'package:retro_eshop/providers/game_providers.dart';
import 'package:retro_eshop/services/drive/drive_api.dart';
import 'package:retro_eshop/services/drive/drive_runtime.dart';

class _Runtime extends DriveRuntime {
  final bool duplicate;
  final int extraFolders;
  _Runtime(this.duplicate, {this.extraFolders = 0});
  @override
  Future<List<DriveFile>> folders(Source source) async => [
        DriveFile(
            id: 'first',
            name: 'SNES',
            mimeType: DriveFile.folderMime,
            parents: ['root-id']),
        if (duplicate)
          DriveFile(
              id: 'second',
              name: 'Super Famicom',
              mimeType: DriveFile.folderMime,
              parents: ['root-id']),
        for (var i = 0; i < extraFolders; i++)
          DriveFile(
              id: 'tool-$i',
              name: 'Tool folder $i with a deliberately long descriptive name',
              mimeType: DriveFile.folderMime,
              parents: ['root-id']),
      ];
}

void main() {
  testWidgets('folder search does not trigger the application I shortcut',
      (tester) async {
    var shortcutsInvoked = 0;
    await tester.pumpWidget(ProviderScope(
        overrides: [
          bootstrappedConfigProvider.overrideWith((ref) => AppConfig.empty),
        ],
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyI): () =>
                shortcutsInvoked++,
          },
          child: MaterialApp(
              home: DriveSourceMappingsScreen(
            source: const Source(
                id: 'source', name: 'Drive', type: SourceType.drive),
            runtime: _Runtime(false),
          )),
        )));
    await tester.pump();
    await tester.tap(find.byType(OutlinedButton).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    expect(shortcutsInvoked, 0);
  });

  testWidgets('folder options are only built for the opened selector',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [
          bootstrappedConfigProvider.overrideWith((ref) => AppConfig.empty),
        ],
        child: MaterialApp(
            home: DriveSourceMappingsScreen(
          source:
              const Source(id: 'source', name: 'Drive', type: SourceType.drive),
          runtime: _Runtime(false, extraFolders: 1335),
        ))));
    await tester.pump();
    // Closed console rows must not lay out every folder's text in hidden stacks.
    expect(find.textContaining('Tool folder'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Not mapped').first);
    await tester.pumpAndSettle();
    expect(tester.widgetList<ListTile>(find.byType(ListTile)).length,
        lessThan(20));
    await tester.enterText(find.byType(TextField), 'Tool folder 99 ');
    await tester.pump();
    expect(
        find.text(
            'Tool folder 99 with a deliberately long descriptive name · tool-99'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final duplicate in [false, true]) {
    testWidgets(
        'empty configuration offers consoles, ambiguous alias=$duplicate',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
          overrides: [
            bootstrappedConfigProvider.overrideWith((ref) => AppConfig.empty),
          ],
          child: MaterialApp(
              home: DriveSourceMappingsScreen(
            source: const Source(
                id: 'source', name: 'Drive', type: SourceType.drive),
            runtime: _Runtime(duplicate),
          ))));
      await tester.pump();
      expect(find.text('Nintendo Entertainment System'), findsWidgets);
      expect(find.text('Super Nintendo'), findsWidgets);
      final rows = tester
          .widgetList<OutlinedButton>(find.byType(OutlinedButton))
          .toList();
      expect(rows.length, greaterThanOrEqualTo(2));
      expect(
          find.descendant(
              of: find.byWidget(rows[0]), matching: find.text('Not mapped')),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byWidget(rows[1]),
              matching: find.text(duplicate ? 'Not mapped' : 'SNES · first')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('folder choice, clear and cancel preserve explicit selections',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [
          bootstrappedConfigProvider.overrideWith((ref) => AppConfig.empty),
        ],
        child: MaterialApp(
            home: DriveSourceMappingsScreen(
          source:
              const Source(id: 'source', name: 'Drive', type: SourceType.drive),
          runtime: _Runtime(false),
        ))));
    await tester.pump();
    final firstSelector = find.byType(OutlinedButton).first;
    await tester.tap(firstSelector);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'SNES · first'));
    await tester.pumpAndSettle();
    expect(
        find.descendant(of: firstSelector, matching: find.text('SNES · first')),
        findsOneWidget);
    await tester.tap(firstSelector);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonB);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(
        find.descendant(of: firstSelector, matching: find.text('SNES · first')),
        findsOneWidget);
    await tester.tap(firstSelector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
        find.descendant(of: firstSelector, matching: find.text('SNES · first')),
        findsOneWidget);
    await tester.tap(firstSelector);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Not mapped'));
    await tester.pumpAndSettle();
    expect(
        find.descendant(of: firstSelector, matching: find.text('Not mapped')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
