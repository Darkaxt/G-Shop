import 'dart:async';

enum DriveAuthorizationIssue {
  setupRequired,
  interactionRequired,
  accountMismatch,
  cancelled,
  unavailable,
}

/// Safe to display/log. Native exception messages and tokens never cross here.
class DriveAuthorizationException implements Exception {
  final DriveAuthorizationIssue issue;
  const DriveAuthorizationException(this.issue);

  @override
  String toString() => 'Drive authorization: ${issue.name}';
}

/// Ephemeral request credential, deliberately without JSON/export methods.
class DriveAuthorizationGrant {
  final String accountId;
  final String accessToken;
  const DriveAuthorizationGrant(this.accountId, this.accessToken);

  @override
  String toString() => 'DriveAuthorizationGrant(redacted)';
}

abstract interface class DriveAuthorizationDriver {
  Future<String?> authenticate({required bool interactive});
  Future<String?> authorize(String accountId, List<String> scopes,
      {required bool interactive});
  Future<void> clearRejectedToken(String accountId, String token);
  Future<void> signOut({required bool revoke});
}

/// One instance per application. Native sign-in has a process-wide session;
/// serialize operations instead of racing account changes with authorization.
class DriveAuthorization {
  static const readOnlyScope = 'https://www.googleapis.com/auth/drive.readonly';
  final DriveAuthorizationDriver _driver;
  Future<void> _tail = Future<void>.value();
  int _sessionGeneration = 0;
  DriveAuthorizationGrant? _grant;

  DriveAuthorization(this._driver);

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    // Keep errors on the caller's future, without poisoning the operation lane.
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  void _requireGeneration(int generation) {
    if (generation != _sessionGeneration) {
      throw const DriveAuthorizationException(
          DriveAuthorizationIssue.cancelled);
    }
  }

  Future<DriveAuthorizationGrant> acquire({
    String? expectedAccountId,
    bool interactive = false,
    String? rejectedToken,
  }) {
    if ((!interactive && expectedAccountId == null) ||
        expectedAccountId?.trim().isEmpty == true) {
      return Future.error(const DriveAuthorizationException(
          DriveAuthorizationIssue.interactionRequired));
    }
    final generation = _sessionGeneration;
    return _serialized(() async {
      try {
        _requireGeneration(generation);
        if (interactive) _grant = null;
        final accountId = await _driver.authenticate(interactive: interactive);
        _requireGeneration(generation);
        if (accountId == null || accountId.isEmpty) {
          _grant = null;
          throw const DriveAuthorizationException(
              DriveAuthorizationIssue.interactionRequired);
        }
        if (expectedAccountId != null && expectedAccountId != accountId) {
          _grant = null;
          throw const DriveAuthorizationException(
              DriveAuthorizationIssue.accountMismatch);
        }
        final current = _grant;
        // A native scope check may issue a token remotely, even when consent
        // already exists. Keep the actual account-bound grant until the API
        // rejects it, never a timer lease. An older concurrent 401 cannot
        // invalidate a newer successful grant in this serialized lane.
        if (current?.accountId == accountId &&
            current!.accessToken != rejectedToken) {
          return current;
        }
        _grant = null;
        if (rejectedToken != null) {
          await _driver.clearRejectedToken(accountId, rejectedToken);
          _requireGeneration(generation);
        }
        final token = await _driver.authorize(accountId, const [readOnlyScope],
            interactive: interactive);
        _requireGeneration(generation);
        if (token == null || token.isEmpty) {
          throw const DriveAuthorizationException(
              DriveAuthorizationIssue.interactionRequired);
        }
        return _grant = DriveAuthorizationGrant(accountId, token);
      } on DriveAuthorizationException {
        rethrow;
      } catch (_) {
        throw const DriveAuthorizationException(
            DriveAuthorizationIssue.unavailable);
      }
    });
  }

  Future<void> signOut({bool revoke = false}) {
    // Invalidate outstanding operations synchronously, then await actual native
    // shutdown. A late consent completion can never publish a usable grant.
    _sessionGeneration++;
    _grant = null;
    return _serialized(() async {
      try {
        await _driver.signOut(revoke: revoke);
      } on DriveAuthorizationException {
        rethrow;
      } catch (_) {
        throw const DriveAuthorizationException(
            DriveAuthorizationIssue.unavailable);
      }
    });
  }
}
