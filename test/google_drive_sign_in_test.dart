import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:retro_eshop/services/drive/drive_authorization.dart';
import 'package:retro_eshop/services/drive/google_drive_sign_in.dart';

class RecordingGooglePlatform extends GoogleSignInPlatform {
  final requests = <AuthorizationRequestDetails>[];
  int interactiveSignIns = 0;
  int lightweightSignIns = 0;
  bool signOutCalled = false;
  bool revokeCalled = false;
  String? clearedToken;
  String? clientId;
  GoogleSignInException? failure;
  bool granted = true;

  AuthenticationResults get result => const AuthenticationResults(
      user:
          GoogleSignInUserData(id: 'account-a', email: 'test@example.invalid'),
      authenticationTokens:
          AuthenticationTokenData(idToken: 'private-id-token'));
  @override
  Future<void> init(InitParameters params) async {
    clientId = params.serverClientId;
  }

  @override
  bool supportsAuthenticate() => true;
  @override
  bool authorizationRequiresUserInteraction() => true;
  @override
  Future<AuthenticationResults> authenticate(
      AuthenticateParameters params) async {
    interactiveSignIns++;
    if (failure != null) throw failure!;
    return result;
  }

  @override
  Future<AuthenticationResults?> attemptLightweightAuthentication(
      AttemptLightweightAuthenticationParameters params) async {
    lightweightSignIns++;
    return result;
  }

  @override
  Future<ClientAuthorizationTokenData?> clientAuthorizationTokensForScopes(
      ClientAuthorizationTokensForScopesParameters params) async {
    requests.add(params.request);
    if (failure != null) throw failure!;
    return granted || params.request.promptIfUnauthorized
        ? const ClientAuthorizationTokenData(
            accessToken: 'private-access-token')
        : null;
  }

  @override
  Future<ServerAuthorizationTokenData?> serverAuthorizationTokensForScopes(
          ServerAuthorizationTokensForScopesParameters params) async =>
      throw StateError('Server tokens must not be requested');
  @override
  Future<void> clearAuthorizationToken(
      ClearAuthorizationTokenParams params) async {
    clearedToken = params.accessToken;
  }

  @override
  Future<void> signOut(SignOutParams params) async {
    signOutCalled = true;
  }

  @override
  Future<void> disconnect(DisconnectParams params) async {
    revokeCalled = true;
  }
}

class _RevocationTransport implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  int status = 200;
  bool closed = false;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return ResponseBody.fromString('private provider details', status);
  }

  @override
  void close({bool force = false}) => closed = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RecordingGooglePlatform platform;
  late DriveAuthorization auth;
  late _RevocationTransport revocation;
  final nativeClears = <String>[];
  const native = MethodChannel('com.retro.rshop/drive_authorization');
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    nativeClears.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(native, (call) async {
      expect(call.method, 'clearTokenIfMicroG');
      nativeClears.add((call.arguments as Map)['token'] as String);
      return true;
    });
    platform = RecordingGooglePlatform();
    GoogleSignInPlatform.instance = platform;
    revocation = _RevocationTransport();
    auth = DriveAuthorization(GoogleDriveSignIn(
        serverClientId: 'test-client-id', revocationAdapter: revocation));
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(native, null);
  });

  test('background reconnect cannot trigger even lightweight account UI',
      () async {
    await expectLater(
        auth.acquire(expectedAccountId: 'account-a'),
        throwsA(isA<DriveAuthorizationException>().having((e) => e.issue,
            'issue', DriveAuthorizationIssue.interactionRequired)));
    expect(platform.interactiveSignIns, 0);
    expect(platform.lightweightSignIns, 0);
    expect(platform.requests, isEmpty);
  });

  test('native authorization is account-bound and read-only, renewal is silent',
      () async {
    await auth.acquire(interactive: true);
    final renewed = await auth.acquire(
        expectedAccountId: 'account-a',
        rejectedToken: 'rejected-private-token');
    expect(renewed.accessToken, 'private-access-token');
    expect(platform.clientId, 'test-client-id');
    expect(platform.interactiveSignIns, 1);
    expect(platform.lightweightSignIns, 0);
    expect(nativeClears, ['rejected-private-token']);
    expect(platform.clearedToken, isNull);
    expect(platform.requests.every((r) => r.userId == 'account-a'), isTrue);
    expect(
        platform.requests.every((r) =>
            r.scopes.length == 1 &&
            r.scopes.single == DriveAuthorization.readOnlyScope),
        isTrue);
    expect(platform.requests.every((r) => !r.promptIfUnauthorized), isTrue);
  });

  test('ordinary Play Services keeps the endorsed native token-clear route',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(native, (_) async => false);
    await auth.acquire(interactive: true);
    await auth.acquire(
        expectedAccountId: 'account-a', rejectedToken: 'old-token');
    expect(platform.clearedToken, 'old-token');
  });

  test('failed microG cache clear is sanitized and does not fetch a token',
      () async {
    await auth.acquire(interactive: true);
    final before = platform.requests.length;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(native, (_) async {
      throw PlatformException(
          code: 'native_error', message: 'private-access-token');
    });
    await expectLater(
        auth.acquire(
            expectedAccountId: 'account-a', rejectedToken: 'old-token'),
        throwsA(isA<DriveAuthorizationException>().having((e) => e.toString(),
            'sanitized', 'Drive authorization: unavailable')));
    expect(platform.requests.length, before);
  });

  test('scope consent occurs only after explicit interactive action', () async {
    platform.granted = false;
    await auth.acquire(interactive: true);
    expect(platform.requests.map((r) => r.promptIfUnauthorized), [false, true]);
    platform.requests.clear();
    await expectLater(
        auth.acquire(expectedAccountId: 'account-a'), throwsException);
    expect(platform.requests.map((r) => r.promptIfUnauthorized), [false]);
  });

  test('native errors cannot expose descriptions or token details', () async {
    platform.failure = const GoogleSignInException(
        code: GoogleSignInExceptionCode.clientConfigurationError,
        description: 'private-access-token',
        details: {'secret': 'private-id-token'});
    await expectLater(
        auth.acquire(interactive: true),
        throwsA(isA<DriveAuthorizationException>().having((e) => e.toString(),
            'sanitized exception', 'Drive authorization: setupRequired')));
  });

  test('missing client configuration fails without invoking native UI',
      () async {
    final missing = DriveAuthorization(GoogleDriveSignIn(serverClientId: ''));
    await expectLater(missing.acquire(interactive: true), throwsException);
    expect(platform.clientId, isNull);
    expect(platform.interactiveSignIns, 0);
  });

  test('signout and revoke clear the in-memory bound account', () async {
    await auth.acquire(interactive: true);
    await auth.signOut(revoke: true);
    expect(platform.revokeCalled, isTrue);
    final request = revocation.requests.single;
    expect(request.method, 'POST');
    expect(request.uri.toString(), 'https://oauth2.googleapis.com/revoke');
    expect(request.followRedirects, isFalse);
    expect(request.data, 'token=private-access-token');
    expect(request.contentType, Headers.formUrlEncodedContentType);
    expect(revocation.closed, isTrue);
    await expectLater(
        auth.acquire(expectedAccountId: 'account-a'), throwsException);
    expect(platform.lightweightSignIns, 0);
    await auth.acquire(interactive: true);
    await auth.signOut();
    expect(platform.signOutCalled, isTrue);
    expect(revocation.requests.length, 1);
  });

  test('server revocation failure never reports a successful local disconnect',
      () async {
    await auth.acquire(interactive: true);
    revocation.status = 500;
    await expectLater(
        auth.signOut(revoke: true),
        throwsA(isA<DriveAuthorizationException>().having((e) => e.toString(),
            'redacted', 'Drive authorization: unavailable')));
    expect(platform.revokeCalled, isFalse);
    expect(revocation.closed, isTrue);
    expect((await auth.acquire(expectedAccountId: 'account-a')).accountId,
        'account-a');
  });

  test('cold-start revoke cannot claim removal of a grant it has not restored',
      () async {
    await expectLater(
        auth.signOut(revoke: true),
        throwsA(isA<DriveAuthorizationException>().having((e) => e.issue,
            'issue', DriveAuthorizationIssue.interactionRequired)));
    expect(platform.revokeCalled, isFalse);
    expect(revocation.requests, isEmpty);
  });
}
