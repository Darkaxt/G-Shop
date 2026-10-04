import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/input/app_intents.dart';
import '../../core/input/console_screen_mixin.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/console_focusable.dart';
import '../../core/widgets/screen_layout.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/metadata_providers.dart';
import '../../services/metadata/metadata_credentials.dart';
import '../../services/metadata/metadata_refresh_jobs.dart';
import 'metadata_review_screen.dart';

/// Normal settings entry, also scoped to the exact selected cached game.
class MetadataSettingsScreen extends ConsumerStatefulWidget {
  final String? systemSlug, gameTitle, editionId;
  final int? cacheRowId;
  const MetadataSettingsScreen(
      {super.key,
      this.systemSlug,
      this.cacheRowId,
      this.gameTitle,
      this.editionId});
  @override
  ConsumerState<MetadataSettingsScreen> createState() =>
      _MetadataSettingsScreenState();
}

class _MetadataSettingsScreenState extends ConsumerState<MetadataSettingsScreen>
    with ConsoleScreenMixin {
  final _username = TextEditingController(),
      _password = TextEditingController();
  final _applicationId = TextEditingController(),
      _applicationSecret = TextEditingController();
  final _software = TextEditingController();
  final _providerFocus = FocusNode();
  String? _scope;
  bool _invalid = false;
  @override
  String get routeId => 'metadata_settings';
  @override
  void initState() {
    super.initState();
    _scope = widget.systemSlug;
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _applicationId.dispose();
    _applicationSecret.dispose();
    _software.dispose();
    _providerFocus.dispose();
    super.dispose();
  }

  @override
  Map<Type, Action<Intent>> get screenActions => {
        BackIntent: CallbackAction<BackIntent>(onInvoke: (_) {
          Navigator.maybePop(context);
          return null;
        }),
        ConfirmIntent: CallbackAction<ConfirmIntent>(onInvoke: (_) {
          final focus = FocusManager.instance.primaryFocus?.context;
          if (focus != null) Actions.maybeInvoke(focus, const ActivateIntent());
          return null;
        }),
        NavigateIntent: CallbackAction<NavigateIntent>(onInvoke: (intent) {
          final focus = FocusManager.instance.primaryFocus;
          if (focus?.context?.widget is EditableText) return null;
          focus?.focusInDirection(switch (intent.direction) {
            GridDirection.up => TraversalDirection.up,
            GridDirection.down => TraversalDirection.down,
            GridDirection.left => TraversalDirection.left,
            GridDirection.right => TraversalDirection.right,
          });
          return null;
        }),
      };

  void _clearFields() {
    _username.clear();
    _password.clear();
    _applicationId.clear();
    _applicationSecret.clear();
    _software.clear();
  }

  Future<void> _save() async {
    final state = ref.read(metadataControlsProvider);
    final controls = ref.read(metadataControlsProvider.notifier);
    final hasUser = _username.text.isNotEmpty || _password.text.isNotEmpty;
    final hasApplication = _applicationId.text.isNotEmpty ||
        _applicationSecret.text.isNotEmpty ||
        _software.text.isNotEmpty;
    final user = ScreenScraperUserCredentials(
        username: _username.text.trim(), password: _password.text);
    final application = ScreenScraperDeveloperCredentials(
        developerId: _applicationId.text.trim(),
        developerPassword: _applicationSecret.text,
        softwareName: _software.text.trim());
    final igdb =
        IgdbCredentials(_applicationId.text.trim(), _applicationSecret.text);
    final valid = state.providerId == 'screenscraper'
        ? ((hasUser && user.isConfigured) ||
                (!hasUser && state.accountConfigured)) &&
            (!hasApplication || application.isConfigured) &&
            (hasUser || hasApplication)
        : igdb.isConfigured;
    if (!valid) {
      setState(() => _invalid = true);
      return;
    }
    setState(() => _invalid = false);
    if (state.providerId == 'screenscraper') {
      await controls.saveScreenScraper(hasUser ? user : null,
          application: hasApplication ? application : null);
    } else {
      await controls.saveIgdb(igdb);
    }
    if (mounted && !ref.read(metadataControlsProvider).error) _clearFields();
  }

  Widget _field(TextEditingController controller, String label, String key,
          {bool secret = false, bool enabled = true}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: TextField(
            key: ValueKey(key),
            controller: controller,
            enabled: enabled,
            obscureText: secret,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: !secret,
            decoration: InputDecoration(
                labelText: label, border: const OutlineInputBorder())),
      );

  Widget _button(String label, String key, VoidCallback? onPressed) =>
      ConsoleFocusable(
          onSelect: onPressed,
          focusScale: 1,
          child: FilledButton(
              key: ValueKey(key),
              style: AppTheme.primaryButtonStyle,
              onPressed: onPressed,
              child: Text(label)));

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final state = ref.watch(metadataControlsProvider);
    final controls = ref.read(metadataControlsProvider.notifier);
    final enabled = !state.busy && !state.loading;
    final ss = state.providerId == 'screenscraper';
    final report = state.report;
    // Include the screen restoration node in its local action/focus boundary.
    return buildWithActions(
        ScreenLayout(
            body: FocusTraversalGroup(
          child: ListView(padding: const EdgeInsets.all(24), children: [
            Row(children: [
              IconButton(
                  tooltip: l.common_back,
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.arrow_back)),
              Expanded(
                  child: Text(l.metadata_setupTitle,
                      style: Theme.of(context).textTheme.headlineSmall)),
            ]),
            const SizedBox(height: 16),
            Center(
                child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l.metadata_accessInfo),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                        key: const ValueKey('metadata-provider'),
                        focusNode: _providerFocus,
                        initialValue: state.providerId,
                        decoration:
                            InputDecoration(labelText: l.metadata_provider),
                        items: const [
                          DropdownMenuItem(
                              value: 'screenscraper',
                              child: Text('ScreenScraper')),
                          DropdownMenuItem(value: 'igdb', child: Text('IGDB'))
                        ],
                        onChanged: !enabled
                            ? null
                            : (id) async {
                                if (id == null) return;
                                _clearFields();
                                setState(() => _invalid = false);
                                await controls.selectProvider(id);
                              }),
                    if (state.loading) const LinearProgressIndicator(),
                    const SizedBox(height: 12),
                    if (ss) ...[
                      Text(
                          '${l.providerForm_username}: ${state.accountConfigured ? l.metadata_saved : l.metadata_notConfigured}'),
                      _field(_username, l.providerForm_username,
                          'metadata-username',
                          enabled: enabled),
                      _field(_password, l.providerForm_password,
                          'metadata-password',
                          secret: true, enabled: enabled),
                    ],
                    Text(
                        '${l.metadata_applicationAccess}: ${state.applicationConfigured ? l.metadata_saved : l.metadata_notConfigured}'),
                    if (ss)
                      ExpansionTile(
                          title: Text(l.metadata_applicationAccess),
                          children: [
                            _field(_applicationId, l.metadata_clientId,
                                'metadata-client-id',
                                enabled: enabled),
                            _field(_applicationSecret, l.metadata_clientSecret,
                                'metadata-client-secret',
                                secret: true, enabled: enabled),
                            _field(_software, l.metadata_softwareName,
                                'metadata-software',
                                enabled: enabled),
                          ])
                    else ...[
                      _field(_applicationId, l.metadata_clientId,
                          'metadata-client-id',
                          enabled: enabled),
                      _field(_applicationSecret, l.metadata_clientSecret,
                          'metadata-client-secret',
                          secret: true, enabled: enabled),
                    ],
                    if (_invalid)
                      Text(l.metadata_invalidInput,
                          style: const TextStyle(color: Colors.amber)),
                    Wrap(spacing: 12, runSpacing: 8, children: [
                      _button(l.common_save, 'metadata-save',
                          enabled ? _save : null),
                      _button(
                          l.metadata_forget,
                          'metadata-forget',
                          enabled &&
                                  (state.accountConfigured ||
                                      state.applicationConfigured)
                              ? () async {
                                  _clearFields();
                                  await controls.removeCredentials();
                                }
                              : null),
                    ]),
                    const Divider(height: 40),
                    if (widget.cacheRowId != null)
                      Text(
                          '${l.metadata_gameScope}: ${widget.gameTitle ?? widget.cacheRowId}')
                    else
                      DropdownButtonFormField<String>(
                          key: const ValueKey('metadata-scope'),
                          initialValue: _scope ?? '',
                          decoration: InputDecoration(
                              labelText: l.metadata_systemScope),
                          items: [
                            DropdownMenuItem(
                                value: '', child: Text(l.metadata_fullScope)),
                            for (final system in {
                              ...state.systems,
                              if (_scope != null) _scope!
                            })
                              DropdownMenuItem(
                                  value: system, child: Text(system))
                          ],
                          onChanged: enabled
                              ? (value) => setState(
                                  () => _scope = value == '' ? null : value)
                              : null),
                    const SizedBox(height: 12),
                    Wrap(spacing: 12, runSpacing: 8, children: [
                      _button(
                          l.metadata_refresh,
                          'metadata-refresh',
                          enabled
                              ? () => controls.refresh(
                                  systemSlug: _scope,
                                  cacheRowId: widget.cacheRowId)
                              : null),
                      _button(
                          l.metadata_pause,
                          'metadata-pause',
                          state.busy && report?.state == 'running'
                              ? controls.pause
                              : null),
                      _button(
                          l.metadata_resume,
                          'metadata-resume',
                          enabled &&
                                  report != null &&
                                  report.state != 'completed'
                              ? controls.resume
                              : null),
                      _button(
                          l.metadata_retryOutcomes,
                          'metadata-retry',
                          enabled &&
                                  report != null &&
                                  [
                                    'unmatched',
                                    'invalidRequest',
                                    'invalidResponse',
                                    'unsupportedPlatform',
                                    'identityChanged'
                                  ].any((s) => (report.counts[s] ?? 0) > 0)
                              ? controls.retryUnresolved
                              : null),
                    ]),
                    const SizedBox(height: 12),
                    _button(
                        l.metadata_openReview,
                        'metadata-open-review',
                        enabled
                            ? () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => MetadataReviewScreen(
                                        systemSlug: _scope,
                                        editionId: widget.editionId,
                                        cacheRowId: widget.cacheRowId)))
                            : null),
                    if (state.busy)
                      const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: LinearProgressIndicator()),
                    if (state.error)
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(l.metadata_controlsError,
                              style: const TextStyle(color: Colors.amber))),
                    if (state.error && report == null)
                      _button(l.common_retry, 'metadata-reload',
                          enabled ? controls.load : null),
                    if (report != null) ...[
                      const SizedBox(height: 16),
                      Text(
                          switch (report.state) {
                            'completed' => l.metadata_jobCompleted,
                            'running' => l.metadata_jobRunning,
                            'queued' => l.metadata_jobQueued,
                            _ => l.downloadStatus_paused,
                          },
                          style: Theme.of(context).textTheme.titleMedium),
                      _coverage(l, report),
                      if (report.blockedStatus != null)
                        Text(switch (report.blockedStatus) {
                          'setupRequired' ||
                          'authenticationRequired' ||
                          'developerAccessRequired' =>
                            l.metadata_configureAccess,
                          'quotaExceeded' ||
                          'throttled' =>
                            l.metadata_quotaWait,
                          _ => l.metadata_offlineWait,
                        }),
                      if (report.notBefore != null)
                        Text(report.notBefore!.toLocal().toString()),
                      Text(l.metadata_completeNote),
                    ],
                  ]),
            )),
          ]),
        )),
        localFocusScope: true);
  }

  Widget _coverage(L l, MetadataRefreshReport report) {
    final counts = report.counts;
    final failed = counts.entries
        .where((e) => !{
              'pending',
              'matched',
              'needsReview',
              'ambiguous',
              'unmatched'
            }.contains(e.key))
        .fold(0, (total, e) => total + e.value);
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Wrap(spacing: 20, runSpacing: 8, children: [
          for (final entry in {
            l.metadata_requested: report.requested,
            l.metadata_matched: counts['matched'] ?? 0,
            l.metadata_review: counts['needsReview'] ?? 0,
            l.metadata_ambiguous: counts['ambiguous'] ?? 0,
            l.metadata_unmatched: counts['unmatched'] ?? 0,
            l.metadata_failed: failed,
            l.metadata_rated: report.rated,
            l.metadata_pending: counts['pending'] ?? 0,
          }.entries)
            Text('${entry.key}: ${entry.value}'),
        ]));
  }
}
