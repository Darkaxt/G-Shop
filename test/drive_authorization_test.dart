import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:retro_eshop/services/drive/drive_authorization.dart';

class FakeDriveAuthorizationDriver implements DriveAuthorizationDriver {
  String? account = 'account-a';
  String? token = 'private-access-token';
  final calls = <String>[];
  Completer<String?>? pendingToken;
  final tokenStarted = Completer<void>();

  @override
  Future<String?> authenticate({required bool interactive}) async {
    calls.add('authenticate:$interactive');
    return account;
  }

  @override
  Future<String?> authorize(String accountId, List<String> scopes,
      {required bool interactive}) async {
    calls.add('authorize:$accountId:${scopes.join(',')}:$interactive');
    if (!tokenStarted.isCompleted) tokenStarted.complete();
    if (pendingToken != null) return await pendingToken!.future;
    return token;
  }

  @override
  Future<void> clearRejectedToken(String accountId, String token) async {
    calls.add('clear:$accountId');
  }

  @override
  Future<void> signOut({required bool revoke}) async {
    calls.add('signOut:$revoke');
    account = null;
  }
}

void main() {
  test('requests only read-only Drive authorization and redacts the grant',
      () async {
    final driver = FakeDriveAuthorizationDriver();
    final auth = DriveAuthorization(driver);
    final grant = await auth.acquire(expectedAccountId: 'account-a');
    expect(grant.accountId, 'account-a');
    expect(grant.accessToken, 'private-access-token');
    expect(grant.toString(), isNot(contains('private-access-token')));
    expect(driver.calls.last,
        'authorize:account-a:https://www.googleapis.com/auth/drive.readonly:false');
  });

  test('never uses another account to fulfill a saved source request',
      () async {
    final driver = FakeDriveAuthorizationDriver()..account = 'account-b';
    final auth = DriveAuthorization(driver);
    await expectLater(
        auth.acquire(expectedAccountId: 'account-a'),
        throwsA(isA<DriveAuthorizationException>().having(
            (e) => e.issue, 'issue', DriveAuthorizationIssue.accountMismatch)));
    expect(driver.calls, ['authenticate:false']);
  });

  test('background requests never launch consent when grant is absent',
      () async {
    final driver = FakeDriveAuthorizationDriver()..token = null;
    final auth = DriveAuthorization(driver);
    await expectLater(
        auth.acquire(expectedAccountId: 'account-a'),
        throwsA(isA<DriveAuthorizationException>().having((e) => e.issue,
            'issue', DriveAuthorizationIssue.interactionRequired)));
    expect(driver.calls.every((call) => call.endsWith(':false')), isTrue);
  });

  test('explicit interactive account selection is allowed', () async {
    final driver = FakeDriveAuthorizationDriver();
    final auth = DriveAuthorization(driver);
    expect((await auth.acquire(interactive: true)).accountId, 'account-a');
    expect(driver.calls.first, 'authenticate:true');
    expect(driver.calls.last, endsWith(':true'));
  });

  test('background acquisition requires an account-bound source', () async {
    final driver = FakeDriveAuthorizationDriver();
    await expectLater(DriveAuthorization(driver).acquire(),
        throwsA(isA<DriveAuthorizationException>()));
    expect(driver.calls, isEmpty);
  });

  test('rejected token is cleared once and only for the matched account',
      () async {
    final driver = FakeDriveAuthorizationDriver();
    final auth = DriveAuthorization(driver);
    await auth.acquire(
        expectedAccountId: 'account-a', rejectedToken: 'old-token');
    expect(
        driver.calls.where((c) => c.startsWith('clear:')), ['clear:account-a']);
    expect(driver.calls.where((c) => c.startsWith('authorize:')).length, 1);
  });

  test('signout invalidates pending grant before waiting for native completion',
      () async {
    final driver = FakeDriveAuthorizationDriver()
      ..pendingToken = Completer<String?>();
    final auth = DriveAuthorization(driver);
    final pending = auth.acquire(expectedAccountId: 'account-a');
    final rejected = expectLater(
        pending,
        throwsA(isA<DriveAuthorizationException>().having(
            (e) => e.issue, 'issue', DriveAuthorizationIssue.cancelled)));
    await driver.tokenStarted.future;
    final signingOut = auth.signOut();
    expect(driver.calls, isNot(contains('signOut:false')));
    driver.pendingToken!.complete('late-token');
    await rejected;
    await signingOut;
    expect(driver.calls.last, 'signOut:false');
  });

  test('revocation uses the explicit native revoke operation', () async {
    final driver = FakeDriveAuthorizationDriver();
    await DriveAuthorization(driver).signOut(revoke: true);
    expect(driver.calls, ['signOut:true']);
  });

  test('a failed operation does not poison serialized future requests',
      () async {
    final driver = FakeDriveAuthorizationDriver()..account = null;
    final auth = DriveAuthorization(driver);
    await expectLater(
        auth.acquire(expectedAccountId: 'account-a'), throwsException);
    driver.account = 'account-a';
    expect((await auth.acquire(expectedAccountId: 'account-a')).accountId,
        'account-a');
  });
}
