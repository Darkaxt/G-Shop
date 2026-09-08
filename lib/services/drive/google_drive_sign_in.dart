import 'package:google_sign_in/google_sign_in.dart';

import 'drive_authorization.dart';

/// Flutter's endorsed plugin delegates Android authentication and scope
/// authorization to Google's native SDK. No embedded client secret is needed.
class GoogleDriveSignIn implements DriveAuthorizationDriver {
  final GoogleSignIn _google;
  final String serverClientId;
  Future<void>? _initialization;
  GoogleSignInAccount? _account;

  GoogleDriveSignIn({required this.serverClientId, GoogleSignIn? google})
      : _google = google ?? GoogleSignIn.instance;

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
        if (existing != null) return existing.accessToken;
        if (!interactive) return null;
        return (await client.authorizeScopes(scopes)).accessToken;
      });

  @override
  Future<void> clearRejectedToken(String accountId, String token) =>
      _native(() => _boundAccount(accountId)
          .authorizationClient
          .clearAuthorizationToken(accessToken: token));

  @override
  Future<void> signOut({required bool revoke}) => _native(() async {
        if (revoke && _account == null) {
          // Android disconnect revokes its process-local account cache only.
          // A cold start cannot truthfully claim a grant was remotely revoked.
          throw const DriveAuthorizationException(
              DriveAuthorizationIssue.interactionRequired);
        }
        _account = null;
        if (revoke) {
          // This is app-wide disconnection of all accounts connected through
          // Google's SDK, not a per-source operation. The settings UI must label
          // it accordingly; deleting a source must never call this implicitly.
          await _google.disconnect();
        } else {
          await _google.signOut();
        }
      });
}
