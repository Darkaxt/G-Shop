import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/services/saves/save_operation_admission.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.retro.rshop/save_operation');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('admission awaits native ownership and releases exactly once', () async {
    final grant = Completer<void>();
    final requested = Completer<void>();
    final calls = <String>[];
    String? id;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      final supplied = (call.arguments as Map)['id'] as String;
      id ??= supplied;
      expect(supplied, id);
      if (call.method == 'acquire') {
        requested.complete();
        await grant.future;
      }
      return null;
    });
    var admitted = false;
    final pending = SaveOperationAdmission(android: true)
        .acquire(CancelToken())
        .then((release) {
      admitted = true;
      return release;
    });
    await requested.future;
    expect(admitted, isFalse);
    expect(calls, ['acquire']);
    grant.complete();
    final release = await pending;
    await release();
    await release();
    expect(calls, ['acquire', 'release']);
  });

  test('cancellation requests removal of its exact native waiter', () async {
    final acquired = Completer<void>();
    final native = Completer<void>();
    final calls = <String>[];
    String? id;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      final supplied = (call.arguments as Map)['id'] as String;
      id ??= supplied;
      expect(supplied, id);
      if (call.method == 'acquire') {
        acquired.complete();
        await native.future;
      }
      if (call.method == 'cancel') {
        native.completeError(PlatformException(code: 'cancelled'));
      }
      return null;
    });
    final cancellation = CancelToken();
    final pending = SaveOperationAdmission(android: true).acquire(cancellation);
    final rejected = expectLater(pending, throwsA(isA<PlatformException>()));
    await acquired.future;
    cancellation.cancel();
    await rejected;
    expect(calls, ['acquire', 'cancel']);
  });
}
