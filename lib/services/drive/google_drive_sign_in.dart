import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'drive_authorization.dart';

/// Flutter's endorsed plugin delegates Android authentication and scope
/// authorization to Google's native SDK. No embedded client secret is needed.
class GoogleDriveSignIn implements DriveAuthorizationDriver {
  static const _nativeAuthorization =
      MethodChannel('com.retro.rshop/drive_authorization');
  final GoogleSignIn _google;
  final String serverClientId;
  final HttpClientAdapter? _revocationAdapter;
  Future<void>? _initialization;
  GoogleSignInAccount? _account;
  String? _lastAccessToken;

  GoogleDriveSignIn(
      {required this.serverClientId,
      GoogleSignIn? google,
      HttpClientAdapter? revocationAdapter})
      : _google = google ?? GoogleSignIn.instance,
        _revocationAdapter = revocationAdapter;

  Future<void> _initialize() {
    if (serverClientId.trim().isEmpty) {
      throw const DriveAuthorizationException(
          DriveAuthorizationIssue.setupRequired);
    }
    return _initialization ??=
        _google.initialize(serverClientId: serverClientId);
  }

  Future<T> _native<T>(Future<T> Function() operation) async {
    try {
      await _initialize();
      return await operation();
    } on GoogleSignInException catch (error) {
      final issue = switch (error.code) {
        GoogleSignInExceptionCode.canceled => DriveAuthorizationIssue.cancelled,
        GoogleSignInExceptionCode.clientConfigurationError ||
        GoogleSignInExceptionCode.providerConfigurationError =>
          DriveAuthorizationIssue.setupRequired,
        GoogleSignInExceptionCode.uiUnavailable =>
          DriveAuthorizationIssue.interactionRequired,
        GoogleSignInExceptionCode.userMismatch =>
          DriveAuthorizationIssue.accountMismatch,
        _ => DriveAuthorizationIssue.unavailable,
      };
      throw DriveAuthorizationException(issue);
    } on DriveAuthorizationException {
      rethrow;
    } catch (_) {
      throw const DriveAuthorizationException(
          DriveAuthorizationIssue.unavailable);
    }
  }

  @override
  Future<String?> authenticate({required bool interactive}) =>
      _native(() async {
        if (interactive) {
          _account = null;
          _lastAccessToken = null;
          _account = await _google.authenticate();
        }
        // Android lightweight authentication may show an account sheet. Only
        // reuse an explicitly connected account for background requests; after
        // process restart, the UI must offer Connect instead of showing consent
        // from a queue worker. Scope/token renewal itself remains noninteractive.
        return _account?.id;
      });

  GoogleSignInAccount _boundAccount(String accountId) {
    final account = _account;
    if (account == null || account.id != accountId) {
      throw const DriveAuthorizationException(
          DriveAuthorizationIssue.accountMismatch);
    }
    return account;
  }

  @override
  Future<String?> authorize(String accountId, List<String> scopes,
          {required bool interactive}) =>
      _native(() async {
        if (scopes.length != 1 ||
            scopes.single != DriveAuthorization.readOnlyScope) {
          throw const DriveAuthorizationException(
              DriveAuthorizationIssue.setupRequired);
        }
        final client = _boundAccount(accountId).authorizationClient;
        final existing = await client.authorizationForScopes(scopes);
        if (existing != null) return _lastAccessToken = existing.accessToken;
        if (!interactive) return null;
        return _lastAccessToken =
            (await client.authorizeScopes(scopes)).accessToken;
      });

  Future<void> _revokeAtGoogle(String token) async {
    // The observed microG revokeAccess implementation only clears local consent.
    // Google's fixed OAuth revocation endpoint confirms the actual app-wide
    // grant removal. Send the ephemeral token in a form body, never a URL/log.
    final http = Dio(BaseOptions(
        baseUrl: 'https://oauth2.googleapis.com/',
        followRedirects: false,
        responseType: ResponseType.stream,
        validateStatus: (_) => true));
    final adapter = _revocationAdapter;
    if (adapter != null) http.httpClientAdapter = adapter;
    try {
      final response = await http.post<ResponseBody>('revoke',
          data: 'token=${Uri.encodeQueryComponent(token)}',
          options: Options(contentType: Headers.formUrlEncodedContentType));
      await response.data?.stream.listen((_) {}).cancel();
      if (response.statusCode != 200) {
        throw const DriveAuthorizationException(
            DriveAuthorizationIssue.unavailable);
      }
    } finally {
      http.close();
    }
  }

  @override
  Future<void> clearRejectedToken(String accountId, String token) =>
      _native(() async {
        final client = _boundAccount(accountId).authorizationClient;
        // microG's identity service omits the clear-token feature, causing the
        // modern SDK to await feature resolution instead of dispatching the call.
        // Select its supported native cache operation BEFORE making that call.
        // Ordinary Play Services and other platforms retain the endorsed route.
        if (defaultTargetPlatform == TargetPlatform.android &&
            await _nativeAuthorization.invokeMethod<bool>(
                    'clearTokenIfMicroG', {'token': token}) ==
                true) {
          return;
        }
        await client.clearAuthorizationToken(accessToken: token);
      });

  @override
  Future<void> signOut({required bool revoke}) => _native(() async {
        if (revoke && (_account == null || _lastAccessToken == null)) {
          // Without a restored credential, a cold start cannot confirm that
          // the app's actual remote grant was revoked.
          throw const DriveAuthorizationException(
              DriveAuthorizationIssue.interactionRequired);
        }
        if (revoke) {
          // This is app-wide disconnection of all accounts connected through
          // Google's SDK, not a per-source operation. The settings UI must label
          // it accordingly; deleting a source must never call this implicitly.
          // Keep the bound credential on server failure so an explicit retry
          // remains possible. The coordinator already invalidated late grants.
          await _revokeAtGoogle(_lastAccessToken!);
          await _google.disconnect();
        } else {
          await _google.signOut();
        }
        _account = null;
        _lastAccessToken = null;
      });
}
