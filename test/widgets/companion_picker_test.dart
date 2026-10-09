import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:retro_eshop/services/storage_service.dart';
import 'package:retro_eshop/features/game_detail/widgets/companion_picker_dialog.dart';

class _RejectWrite extends InMemorySharedPreferencesStore {
  _RejectWrite() : super.empty();
  @override
  Future<bool> setValue(String type, String key, Object value) async => false;
}

void main() {
  late StorageService storage;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  Future<void> initialize() async {
    // Construct the serialized preference lane inside the widget's clock zone.
    storage = StorageService();
    await storage.init();
  }

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: Builder(
      builder: (context) => TextButton(
          onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => CompanionPickerDialog(
                  storage: storage,
                  editionId: 'edition-one',
                  applications: Future.value([
                    {
                      'component': 'com.example.reader/.MainActivity',
                      'label': 'Reader'
                    },
                    {
                      'component': 'com.example.notes/.MainActivity',
                      'label': 'Notes'
                    },
                  ]))),
          child: const Text('Configure')),
    ))));
    await tester.tap(find.text('Configure'));
    await tester.pumpAndSettle();
  }

  testWidgets('touch selects one edition without changing another',
      (tester) async {
    await initialize();
    await storage.setCompanion('edition-two', 'com.example.other/.Main');
    await open(tester);
    await tester.tap(find.text('Reader'));
    await tester.pumpAndSettle();
    await tester.pump(Duration.zero);
    expect(storage.getCompanion('edition-one'),
        'com.example.reader/.MainActivity');
    expect(storage.getCompanion('edition-two'), 'com.example.other/.Main');
  });

  testWidgets(
      'controller changes the association and explicit clear removes it',
      (tester) async {
    await initialize();
    await storage.setCompanion(
        'edition-one', 'com.example.notes/.MainActivity');
    await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(storage.getCompanion('edition-one'),
        'com.example.reader/.MainActivity');
    await tester.tap(find.text('Configure'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No companion · ordinary launch'));
    await tester.pumpAndSettle();
    await tester.pump(Duration.zero);
    expect(storage.getCompanion('edition-one'), isNull);
  });

  testWidgets('controller cancel preserves the existing association',
      (tester) async {
    await initialize();
    await storage.setCompanion(
        'edition-one', 'com.example.reader/.MainActivity');
    await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.pump(Duration.zero);
    expect(storage.getCompanion('edition-one'),
        'com.example.reader/.MainActivity');
    expect(find.text('Companion on bottom screen'), findsNothing);
  });

  testWidgets('failed durable write stays open without claiming a saved target',
      (tester) async {
    await initialize();
    await open(tester);
    final original = SharedPreferencesStorePlatform.instance;
    addTearDown(() => SharedPreferencesStorePlatform.instance = original);
    SharedPreferencesStorePlatform.instance = _RejectWrite();
    await tester.tap(find.text('Reader'));
    await tester.pumpAndSettle();
    expect(storage.getCompanion('edition-one'), isNull);
    expect(find.text('Could not confirm saved companion.'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.pump(Duration.zero);
  });
}
