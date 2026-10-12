import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/features/settings/save_backup_settings_screen.dart';
import 'package:retro_eshop/services/saves/save_capture.dart';
import '../helpers/pump_helpers.dart';

void main() {
  const channel = MethodChannel('com.retro.rshop/save_capture');
  const directory = '/storage/emulated/0/PSP/PPSSPP_STATE';
  const slot = 'ULUS10041_1.00_0.ppst';
  final calls = <MethodCall>[];
  setUp(() => calls.clear());
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  testWidgets('PPSSPP discovers configured state folder without manual mapping',
      (tester) async {
    var pickerCalls = 0, mappings = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'ppssppSaveSettings') return {'directory': directory};
      if (call.method == 'ppssppNames') return [slot];
      return null;
    });
    await tester.pumpWidget(createTestApp(Scaffold(
        body: SingleChildScrollView(
            child: StandaloneSaveMappingPanel(
                title: 'Reviewed PSP edition',
                capture: SaveCapture(),
                chooseDirectory: () async {
                  pickerCalls++;
                  return null;
                },
                onMapped: (_, __) async {
                  mappings++;
                })))));
    await tester.pumpAndSettle();
    expect(calls.map((c) => c.method), ['ppssppSaveSettings', 'ppssppNames']);
    expect(calls.last.arguments, {'directory': directory});
    expect(find.text(directory), findsOneWidget);
    expect(pickerCalls, 0);
    expect(mappings, 0);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('ppsspp-map-save')))
            .onPressed,
        isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('root refusal preserves PPSSPP manual selection and retry',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'ppssppSaveSettings') {
        throw PlatformException(code: 'root_unavailable');
      }
      if (call.method == 'ppssppNames') return [slot];
      return null;
    });
    await tester.pumpWidget(createTestApp(Scaffold(
        body: SingleChildScrollView(
            child: StandaloneSaveMappingPanel(
                title: 'Reviewed PSP edition',
                capture: SaveCapture(),
                chooseDirectory: () async => directory,
                onMapped: (_, __) async {})))));
    await tester.pumpAndSettle();
    expect(find.textContaining('Magisk'), findsOneWidget);
    expect(find.byKey(const ValueKey('ppsspp-map-discover')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('ppsspp-map-folder')));
    await tester.tap(find.byKey(const ValueKey('ppsspp-map-folder')));
    await tester.pumpAndSettle();
    expect(find.text(directory), findsOneWidget);
    expect(calls.last.method, 'ppssppNames');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'PSP in-game saves discover complete folders separately from states',
      (tester) async {
    const parent = '/storage/emulated/0/PSP/SAVEDATA';
    const folder = 'ULUS10041DATA00';
    String? mappedDirectory, mappedName;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'ppssppSaveSettings') return {'directory': directory};
      if (call.method == 'ppssppSavedataFolders') return [folder];
      return null;
    });
    await tester.pumpWidget(createTestApp(Scaffold(
        body: SingleChildScrollView(
            child: StandaloneSaveMappingPanel(
                pspSavedata: true,
                title: 'Reviewed PSP edition',
                capture: SaveCapture(),
                chooseDirectory: () async =>
                    throw StateError('Unexpected manual picker'),
                onMapped: (directory, name) async {
                  mappedDirectory = directory;
                  mappedName = name;
                })))));
    await tester.pumpAndSettle();
    expect(calls.map((call) => call.method),
        ['ppssppSaveSettings', 'ppssppSavedataFolders']);
    expect(calls.last.arguments, {'directory': parent});
    expect(find.text('Choose a PPSSPP in-game save'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('ppsspp-map-slot')));
    await tester.tap(find.byKey(const ValueKey('ppsspp-map-slot')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(folder).last);
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.byKey(const ValueKey('ppsspp-map-confirm')));
    await tester.tap(find.byKey(const ValueKey('ppsspp-map-confirm')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('ppsspp-map-save')));
    await tester.tap(find.byKey(const ValueKey('ppsspp-map-save')));
    await tester.pumpAndSettle();
    expect(mappedDirectory, '$parent/$folder');
    expect(mappedName, folder);
    expect(tester.takeException(), isNull);
  });
}
