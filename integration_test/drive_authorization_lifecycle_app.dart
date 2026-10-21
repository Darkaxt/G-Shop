import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:g_shop/models/config/drive_source_config.dart';
import 'package:g_shop/models/config/source.dart';
import 'package:g_shop/services/config_parser.dart';
import 'package:g_shop/services/drive/drive_api.dart';
import 'package:g_shop/services/drive/drive_authorization.dart';
import 'package:g_shop/services/drive/google_drive_sign_in.dart';

/// Manually driven real native/API proof. No normal bootstrap, database, queue,
/// source writes, media requests, token persistence or mock authorization.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: _Proof()));
}

class _TraceDriver implements DriveAuthorizationDriver {
  final DriveAuthorizationDriver delegate;
  final void Function(String) record;
  _TraceDriver(this.delegate, this.record);

  @override
  Future<String?> authenticate({required bool interactive}) async {
    record('ENTER_native_authenticate');
    final value = await delegate.authenticate(interactive: interactive);
    record('EXIT_native_authenticate');
    return value;
  }

  @override
  Future<String?> authorize(String accountId, List<String> scopes,
      {required bool interactive}) async {
    record('ENTER_native_authorize');
    final value =
        await delegate.authorize(accountId, scopes, interactive: interactive);
    record('EXIT_native_authorize');
    return value;
  }

  @override
  Future<void> clearRejectedToken(String accountId, String token) async {
    record('ENTER_native_clear');
    await delegate.clearRejectedToken(accountId, token);
    record('EXIT_native_clear');
  }

  @override
  Future<void> signOut({required bool revoke}) async {
    record('ENTER_native_signOut');
    await delegate.signOut(revoke: revoke);
    record('EXIT_native_signOut');
  }
}

class _Proof extends StatefulWidget {
  const _Proof();
  @override
  State<_Proof> createState() => _ProofState();
}

class _ProofState extends State<_Proof> {
  DriveSourceConfig? _config;
  DriveAuthorization? _auth;
  DriveAuthorizationGrant? _grant;
  bool _busy = false;
  StreamIterator<void>? _expiryChecks;
  bool _expiryCancelled = false;
  final _messages = <String>[];

  void _record(String message) {
    // Only fixed proof codes and HTTP status cross the diagnostic boundary.
    debugPrint('AUTH_PROOF $message');
    if (mounted) {
      setState(() {
        if (_messages.length == 100) _messages.removeAt(0);
        _messages.add(message);
      });
    }
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await operation();
    } on DriveAuthorizationException catch (error) {
      _record('authorization_${error.issue.name}');
    } on DriveApiException catch (error) {
      _record('api_${error.issue.name}');
    } catch (_) {
      _record('FAILED_unclassified');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _require(bool condition) {
    if (!condition) throw StateError('proof_condition');
  }

  Future<void> _load() async {
    _require(kDebugMode && Platform.isAndroid);
    _require((await PackageInfo.fromPlatform()).packageName ==
        'com.darkaxt.rshop.debug');
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/config.json');
    _require(await file.length() <= 5 * 1024 * 1024);
    // Read the primary only: config recovery must not mutate normal sources.
    final config = ConfigParser.parse(await file.readAsString());
    final sources = config.sources.where((s) => s.type == SourceType.drive);
    _require(sources.isNotEmpty);
    final drive = sources.first.drive!;
    _require(drive.isConfigured);
    _config = drive;
    _auth = DriveAuthorization(_TraceDriver(
        GoogleDriveSignIn(serverClientId: drive.serverClientId), _record));
    _record('READY_saved_source_read_only');
  }

  Future<void> _root() async {
    _record('ENTER_real_root');
    final api = DriveApi(authorization: _auth!, accountId: _config!.accountId);
    try {
      _require((await api.getFile('root')).isFolder);
      _record('EXIT_real_root');
    } finally {
      api.close();
    }
  }

  Future<void> _connect() async {
    _require(_auth != null);
    _grant = await _auth!
        .acquire(expectedAccountId: _config!.accountId, interactive: true);
    await _root();
    _record('PASS_native_connected_real_root');
  }

  Future<void> _renew() async {
    _require(_grant != null);
    _grant = await _auth!.acquire(
        expectedAccountId: _config!.accountId,
        rejectedToken: _grant!.accessToken);
    await _root();
    // Explicitly NOT proof of an elapsed access-token expiry.
    _record('PASS_native_cache_clear_noninteractive_root');
  }

  Future<int> _heldRootStatus(DriveAuthorizationGrant grant) async {
    final http = HttpClient();
    try {
      final request = await http.getUrl(Uri.https(
          'www.googleapis.com', '/drive/v3/files/root', {'fields': 'id'}));
      request.followRedirects = false;
      request.headers
          .set(HttpHeaders.authorizationHeader, 'Bearer ${grant.accessToken}');
      final response = await request.close();
      final status = response.statusCode;
      await response.listen((_) {}).cancel();
      return status;
    } finally {
      http.close(force: true);
    }
  }

  Future<void> _observeExpiry() async {
    _require(_grant != null && _expiryChecks == null);
    final held = _grant!;
    _require(await _heldRootStatus(held) == 200);
    _record('START_held_grant_valid_HTTP200');
    _expiryCancelled = false;
    // Read-only health observations, not an expiry deadline or success timer.
    // Only Google's actual rejection allows renewal proof. No native cache
    // invalidation, revocation or token persistence occurs while observing.
    final checks = StreamIterator<void>(
        Stream<void>.periodic(const Duration(minutes: 1), (_) {}));
    _expiryChecks = checks;
    try {
      while (await checks.moveNext()) {
        final status = await _heldRootStatus(held);
        if (_expiryCancelled) break;
        if (status == 200) {
          _record('WAIT_held_grant_still_valid_HTTP200');
          continue;
        }
        _require(status == 401);
        _record('OBSERVED_held_grant_rejected_HTTP401');
        _grant = await _auth!.acquire(
            expectedAccountId: _config!.accountId,
            rejectedToken: held.accessToken);
        _require(_grant!.accessToken != held.accessToken);
        await _root();
        _record('PASS_elapsed_rejection_noninteractive_renewal_root');
        return;
      }
      _record('CANCELLED_expiry_observation');
    } finally {
      await checks.cancel();
      _expiryChecks = null;
    }
  }

  Future<void> _cancelExpiry() async {
    _expiryCancelled = true;
    await _expiryChecks?.cancel();
    // _run remains busy until any in-flight read-only request has completed.
  }

  Future<void> _mismatch() async {
    _require(_grant != null);
    try {
      await _auth!
          .acquire(expectedAccountId: '${_config!.accountId}-foreign-proof');
      _record('FAILED_foreign_binding_accepted');
    } on DriveAuthorizationException catch (error) {
      _require(error.issue == DriveAuthorizationIssue.accountMismatch);
      _record('PASS_native_foreign_binding_rejected');
    }
    await _root();
    _record('PASS_original_account_still_bound');
  }

  Future<void> _revoke() async {
    _require(_grant != null);
    final previous = _grant!;
    await _auth!.signOut(revoke: true);
    _grant = null;
    try {
      await _auth!.acquire(expectedAccountId: _config!.accountId);
      _record('FAILED_revoked_background_accepted');
      return;
    } on DriveAuthorizationException catch (error) {
      _require(error.issue == DriveAuthorizationIssue.interactionRequired);
      _record('PASS_revoked_background_requires_interaction');
    }
    final http = HttpClient();
    try {
      final request = await http.getUrl(Uri.https(
          'www.googleapis.com', '/drive/v3/files/root', {'fields': 'id'}));
      request.followRedirects = false;
      request.headers.set(
          HttpHeaders.authorizationHeader, 'Bearer ${previous.accessToken}');
      final response = await request.close();
      final status = response.statusCode;
      await response.listen((_) {}).cancel();
      _record(status == 401 || status == 403
          ? 'PASS_server_revoked_previous_grant_HTTP$status'
          : 'FAILED_server_previous_grant_HTTP$status');
    } finally {
      http.close(force: true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Drive native authorization proof')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Read-only metadata only. Select the existing default '
                'account. After Revoke, cancel the scope prompt once, then '
                'Connect again to restore the grant. Tokens stay in memory.'),
            Wrap(spacing: 12, children: [
              for (final action in <String, Future<void> Function()>{
                'Load': _load,
                'Connect': _connect,
                'Renew cached token': _renew,
                'Observe natural expiry': _observeExpiry,
                'Foreign binding': _mismatch,
                'Revoke': _revoke,
              }.entries)
                ElevatedButton(
                    onPressed: _busy ? null : () => _run(action.value),
                    child: Text(action.key)),
              if (_expiryChecks != null)
                ElevatedButton(
                    onPressed: _cancelExpiry,
                    child: const Text('Cancel expiry observation')),
            ]),
            for (final message in _messages) Text(message),
            if (_busy) const Text('Awaiting native/API completion'),
          ]),
        ),
      );
}
