import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/services/drive/drive_authorization.dart';

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
  test('backup consent requests only drive.file without account reselection',
      () async {
    final driver = FakeDriveAuthorizationDriver();
    final auth = DriveAuthorization(driver);
    final grant =
        await auth.requestBackupConsent(expectedAccountId: 'account-a');
    expect(grant.accountId, 'account-a');
    expect(grant.toString(), isNot(contains('private-access-token')));
    expect(driver.calls, [
      'authenticate:false',
      'authorize:account-a:https://www.googleapis.com/auth/drive.file:true',
    ]);
  });

  test('ROM and backup grants cannot satisfy each other', () async {
    final driver = FakeDriveAuthorizationDriver()..token = 'rom-token';
    final auth = DriveAuthorization(driver);
    await auth.acquire(expectedAccountId: 'account-a');
    driver.token = 'backup-token';
    await auth.requestBackupConsent(expectedAccountId: 'account-a');
    expect((await auth.acquire(expectedAccountId: 'account-a')).accessToken,
        'rom-token');
    expect(
        (await auth.acquireBackup(expectedAccountId: 'account-a')).accessToken,
        'backup-token');
    expect(driver.calls.where((c) => c.startsWith('authorize:')), hasLength(2));
  });

  test('silent backup never opens consent or accepts another account',
      () async {
    final driver = FakeDriveAuthorizationDriver()..token = null;
    final auth = DriveAuthorization(driver);
    await expectLater(auth.acquireBackup(expectedAccountId: 'account-a'),
        throwsA(isA<DriveAuthorizationException>()));
    expect(driver.calls.last,
        'authorize:account-a:https://www.googleapis.com/auth/drive.file:false');
    driver.account = 'account-b';
    driver.calls.clear();
    await expectLater(
        auth.requestBackupConsent(expectedAccountId: 'account-a'),
        throwsA(isA<DriveAuthorizationException>().having(
            (e) => e.issue, 'issue', DriveAuthorizationIssue.accountMismatch)));
    expect(driver.calls, ['authenticate:false']);
  });

  test('signout cancels pending backup consent before it can publish a grant',
      () async {
    final driver = FakeDriveAuthorizationDriver()
      ..pendingToken = Completer<String?>();
    final auth = DriveAuthorization(driver);
    final pending = auth.requestBackupConsent(expectedAccountId: 'account-a');
    final rejected = expectLater(
        pending,
        throwsA(isA<DriveAuthorizationException>().having(
            (e) => e.issue, 'issue', DriveAuthorizationIssue.cancelled)));
    await driver.tokenStarted.future;
    final signingOut = auth.signOut();
    driver.pendingToken!.complete('late-backup-token');
    await rejected;
    await signingOut;
    driver.account = 'account-a';
    driver.pendingToken = null;
    driver.token = 'new-backup-token';
    expect(
        (await auth.acquireBackup(expectedAccountId: 'account-a')).accessToken,
        'new-backup-token');
  });

  test(
      'account-bound requests reuse an in-memory grant without native reauthorization',
      () async {
    final driver = FakeDriveAuthorizationDriver();
    final auth = DriveAuthorization(driver);
    final first = await auth.acquire(expectedAccountId: 'account-a');
    final second = await auth.acquire(expectedAccountId: 'account-a');
    expect(second.accessToken, first.accessToken);
    expect(
        driver.calls.where((c) => c.startsWith('authenticate:')), hasLength(2));
    expect(driver.calls.where((c) => c.startsWith('authorize:')), hasLength(1));
  });

  test(
      'a rejected cached token renews once and a stale rejection retains the new grant',
      () async {
    final driver = FakeDriveAuthorizationDriver()..token = 'token-one';
    final auth = DriveAuthorization(driver);
    await auth.acquire(expectedAccountId: 'account-a');
    driver.token = 'token-two';
    final results = await Future.wait([
      auth.acquire(expectedAccountId: 'account-a', rejectedToken: 'token-one'),
      auth.acquire(expectedAccountId: 'account-a', rejectedToken: 'token-one'),
    ]);
    expect(results.map((g) => g.accessToken), ['token-two', 'token-two']);
    expect(driver.calls.where((c) => c.startsWith('clear:')), hasLength(1));
    expect(driver.calls.where((c) => c.startsWith('authorize:')), hasLength(2));
  });

  test('interactive reconnect retires the cached grant', () async {
    final driver = FakeDriveAuthorizationDriver()..token = 'token-one';
    final auth = DriveAuthorization(driver);
    await auth.acquire(expectedAccountId: 'account-a');
    driver.token = 'token-two';
    expect(
        (await auth.acquire(expectedAccountId: 'account-a', interactive: true))
            .accessToken,
        'token-two');
    expect((await auth.acquire(expectedAccountId: 'account-a')).accessToken,
        'token-two');
    expect(driver.calls.where((c) => c.startsWith('authorize:')), hasLength(2));
  });

  test('a cached grant cannot cross a connected-account change', () async {
    final driver = FakeDriveAuthorizationDriver();
    final auth = DriveAuthorization(driver);
    await auth.acquire(expectedAccountId: 'account-a');
    driver.account = 'account-b';
    await expectLater(
        auth.acquire(expectedAccountId: 'account-a'),
        throwsA(isA<DriveAuthorizationException>().having(
            (e) => e.issue, 'issue', DriveAuthorizationIssue.accountMismatch)));
    expect(driver.calls.where((c) => c.startsWith('authorize:')), hasLength(1));
  });

  test(
      'signout retires a previously cached grant even when the same account reconnects',
      () async {
    final driver = FakeDriveAuthorizationDriver()..token = 'token-one';
    final auth = DriveAuthorization(driver);
    await auth.acquire(expectedAccountId: 'account-a');
    await auth.signOut();
    driver.account = 'account-a';
    driver.token = 'token-two';
    expect((await auth.acquire(expectedAccountId: 'account-a')).accessToken,
        'token-two');
    expect(driver.calls.where((c) => c.startsWith('authorize:')), hasLength(2));
  });

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
