import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dio/dio.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart'
    show
        GoogleSignInPlatform,
        AuthorizationRequestDetails,
        ClientAuthorizationTokensForScopesParameters;

import 'drive_authorization.dart';

/// Flutter's endorsed plugin delegates Android authentication and scope
/// authorization to Google's native SDK. No embedded client secret is needed.
class GoogleDriveSignIn implements DriveAuthorizationDriver {
  static const _nativeAuthorization =
      MethodChannel('com.retro.rshop/drive_authorization');
  final GoogleSignIn _google;
  final String serverClientId;
  final HttpClientAdapter? _revocationAdapter;
  final FlutterSecureStorage _storage;
  Future<void>? _initialization;
  GoogleSignInAccount? _account;
  ({String id, String email})? _accountReference;
  bool _restorationAttempted = false;
  String? _lastAccessToken;

  String get _accountReferenceKey =>
      'drive_account_reference_v1:${Uri.encodeComponent(serverClientId)}';

  GoogleDriveSignIn(
      {required this.serverClientId,
      GoogleSignIn? google,
      FlutterSecureStorage? storage,
      HttpClientAdapter? revocationAdapter})
      : _google = google ?? GoogleSignIn.instance,
        _storage = storage ??
            const FlutterSecureStorage(
                aOptions: AndroidOptions(encryptedSharedPreferences: true)),
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
          _accountReference = null;
          _restorationAttempted = true;
          _lastAccessToken = null;
          await _storage.delete(key: _accountReferenceKey);
          _account = await _google.authenticate();
          _accountReference = (id: _account!.id, email: _account!.email);
        } else if (_accountReference == null &&
            !_restorationAttempted &&
            defaultTargetPlatform == TargetPlatform.android) {
          final saved = await _storage.read(key: _accountReferenceKey);
          if (saved != null) {
            final decoded = jsonDecode(saved) as Map<String, dynamic>;
            final id = decoded['id'];
            final email = decoded['email'];
            if (decoded.length != 2 ||
                id is! String ||
                id.trim().isEmpty ||
                email is! String ||
                email.trim().isEmpty) {
              throw const DriveAuthorizationException(
                  DriveAuthorizationIssue.interactionRequired);
            }
            _accountReference = (id: id, email: email);
          }
          _restorationAttempted = true;
        }
        // The reference is not a credential or a usable grant. On Android the
        // existing native authorization API can obtain a token for that exact
        // account without Credential Manager (whose lightweight flow can show
        // a chooser). The coordinator checks the source's expected ID before
        // any token request. Native consent is still required if access is gone.
        return _accountReference?.id;
      });

  ({String id, String email}) _boundAccount(String accountId) {
    final account = _accountReference;
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
            (scopes.single != DriveAuthorization.readOnlyScope &&
                scopes.single != DriveAuthorization.backupFileScope)) {
          throw const DriveAuthorizationException(
              DriveAuthorizationIssue.setupRequired);
        }
        final account = _boundAccount(accountId);
        String? token;
        final liveAccount = _account;
        if (liveAccount != null) {
          final client = liveAccount.authorizationClient;
          token = (await client.authorizationForScopes(scopes))?.accessToken;
          if (token == null && interactive) {
            token = (await client.authorizeScopes(scopes)).accessToken;
          }
        } else {
          // The endorsed Android platform implementation uses AuthorizationClient
          // with setAccount(email). Background authorization never starts a
          // resolution. Only explicit backup setup may resolve its new scope;
          // it retains the exact saved account, without credential selection.
          token = (await GoogleSignInPlatform.instance
                  .clientAuthorizationTokensForScopes(
                      ClientAuthorizationTokensForScopesParameters(
                          request: AuthorizationRequestDetails(
                              scopes: scopes,
                              userId: account.id,
                              email: account.email,
                              promptIfUnauthorized: interactive &&
                                  scopes.single ==
                                      DriveAuthorization.backupFileScope))))
              ?.accessToken;
        }
        if (token == null || token.isEmpty) return null;
        if (defaultTargetPlatform == TargetPlatform.android) {
          // Store only the explicit account selection, never access/ID/refresh
          // tokens. A restored reference cannot itself authorize a request.
          await _storage.write(
              key: _accountReferenceKey,
              value: jsonEncode({'id': account.id, 'email': account.email}));
        }
        return _lastAccessToken = token;
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
        _boundAccount(accountId);
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
        await _google.authorizationClient
            .clearAuthorizationToken(accessToken: token);
      });

  @override
  Future<void> signOut({required bool revoke}) => _native(() async {
        if (revoke && (_accountReference == null || _lastAccessToken == null)) {
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
          await _storage.delete(key: _accountReferenceKey);
          await _google.disconnect();
        } else {
          await _storage.delete(key: _accountReferenceKey);
          await _google.signOut();
        }
        _account = null;
        _accountReference = null;
        _restorationAttempted = true;
        _lastAccessToken = null;
      });
}
