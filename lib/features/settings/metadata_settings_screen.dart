import 'dart:io';
import 'package:path/path.dart' as p;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/input/app_intents.dart';
import '../../core/input/console_screen_mixin.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/console_focusable.dart';
import '../../core/widgets/screen_layout.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/metadata_providers.dart';
import '../../providers/library_providers.dart';
import '../../services/metadata/metadata_credentials.dart';
import '../../services/metadata/metadata_refresh_jobs.dart';
import 'metadata_review_screen.dart';
import 'metadata_progress_feedback.dart';

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
  bool _esDeClosed = false;
  String? _esDeTarget;
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

  Future<void> _selectSharedStorage() async {
    final controls = ref.read(metadataControlsProvider.notifier);
    var selected = false;
    await controls.selectSharedStorage(() async {
      if (Platform.isAndroid &&
          !(await Permission.manageExternalStorage.request()).isGranted) {
        return null;
      }
      final path = await FilePicker.platform.getDirectoryPath();
      selected = path != null;
      return path == null ? null : Directory(path);
    });
    if (!mounted || !selected) return;
    final state = ref.read(metadataControlsProvider);
    if (state.error || state.sharedDirectory == null) return;
    // Selection/migration has joined; do not dispose an active metadata worker.
    ref.invalidate(sharedMetadataStoreProvider);
    ref.invalidate(metadataArtworkCacheProvider);
    ref.invalidate(metadataControlsProvider);
  }

  Future<void> _mapEsDe() async {
    if (widget.cacheRowId == null || widget.editionId == null) return;
    final l = L.of(context);
    if (Platform.isAndroid &&
        !(await Permission.manageExternalStorage.request()).isGranted) {
      return;
    }
    final romRoot = await FilePicker.platform
        .getDirectoryPath(dialogTitle: l.metadata_esDeRomRoot);
    if (!mounted || romRoot == null) return;
    final gamelistRoot = await FilePicker.platform
        .getDirectoryPath(dialogTitle: l.metadata_esDeGamelist);
    if (!mounted || gamelistRoot == null) return;
    final mediaRoot = await FilePicker.platform
        .getDirectoryPath(dialogTitle: l.metadata_esDeMediaRoot);
    if (!mounted || mediaRoot == null) return;
    await ref.read(metadataControlsProvider.notifier).mapEsDeEdition(
        cacheRowId: widget.cacheRowId!,
        editionId: widget.editionId!,
        romRoot: Directory(romRoot),
        mediaRoot: Directory(mediaRoot),
        gamelist: File(p.join(gamelistRoot, 'gamelist.xml')));
  }

  Future<void> _reviewEsDeArtwork() async {
    if (widget.editionId == null) return;
    final l = L.of(context);
    final selected = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'webp'],
        allowMultiple: false,
        withData: false,
        dialogTitle: l.metadata_esDeReviewArtwork);
    final path = selected?.files.single.path;
    if (!mounted || path == null) return;
    final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(l.metadata_esDeReviewArtwork),
                content: Text('${l.metadata_esDeReviewArtworkHelp}\n\n'
                    '${widget.gameTitle ?? widget.editionId}\n'
                    '${widget.systemSlug ?? ''}\n$path'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(l.common_cancel)),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(l.metadata_esDeReviewArtwork)),
                ]));
    if (!mounted || accepted != true) return;
    await ref
        .read(metadataControlsProvider.notifier)
        .reviewEsDeArtwork(editionId: widget.editionId!, source: File(path));
  }

  Widget _esDeSection(L l, MetadataControlsState state, bool enabled) {
    final selected = state.esDeTargets.contains(_esDeTarget)
        ? _esDeTarget
        : state.esDeTargets.firstOrNull;
    return ExpansionTile(
        key: const ValueKey('metadata-esde-section'),
        title: Text(l.metadata_esDe),
        children: [
          Text(l.metadata_esDeHelp),
          if (widget.cacheRowId == null || widget.editionId == null)
            Text(l.metadata_esDeNoMapping),
          _button(
              l.metadata_esDeMap,
              'metadata-esde-map',
              enabled &&
                      state.sharedDirectory != null &&
                      widget.editionId != null &&
                      widget.cacheRowId != null
                  ? _mapEsDe
                  : null),
          _button(
              l.metadata_esDeReviewArtwork,
              'metadata-esde-review-artwork',
              enabled &&
                      state.sharedDirectory != null &&
                      widget.editionId != null
                  ? _reviewEsDeArtwork
                  : null),
          if (selected != null)
            DropdownButton<String>(
                key: const ValueKey('metadata-esde-target'),
                value: selected,
                isExpanded: true,
                items: state.esDeTargets
                    .map((path) => DropdownMenuItem(
                        value: path,
                        child: Text(path,
                            maxLines: 2, overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: enabled
                    ? (value) => setState(() => _esDeTarget = value)
                    : null),
          CheckboxListTile(
              key: const ValueKey('metadata-esde-closed'),
              title: Text(l.metadata_esDeClosed),
              value: _esDeClosed,
              onChanged: enabled
                  ? (value) => setState(() => _esDeClosed = value ?? false)
                  : null),
          _button(
              l.metadata_esDePublish,
              'metadata-esde-publish',
              enabled && selected != null && _esDeClosed
                  ? () => ref
                      .read(metadataControlsProvider.notifier)
                      .publishEsDe(File(selected), esDeClosed: _esDeClosed)
                  : null),
          if (state.esDeReport case final report?) ...[
            Text({'published', 'upToDate'}.contains(report.status)
                ? l.metadata_esDePublished
                : l.metadata_esDeConflict),
            for (final conflict in report.conflicts)
              Text(
                  '${conflict.relativeRomPath}${conflict.field == null ? '' : ' · ${conflict.field}'}'),
          ],
        ]);
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

  void _openReview() => Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => MetadataReviewScreen(
              systemSlug: _scope,
              editionId: widget.editionId,
              cacheRowId: widget.cacheRowId)));

  Future<void> _rediscover() async {
    await ref.read(metadataControlsProvider.notifier).rediscoverMatch(
        cacheRowId: widget.cacheRowId!, editionId: widget.editionId!);
    if (mounted && !ref.read(metadataControlsProvider).error) _openReview();
  }

  Future<void> _selectSavedJob() async {
    final l = L.of(context);
    final controls = ref.read(metadataControlsProvider.notifier);
    var page = controls.savedJobs();
    final selected = await showDialog<int>(
        context: context,
        builder: (dialogContext) => Actions(
            actions: screenActions,
            child: StatefulBuilder(builder: (context, update) {
              return AlertDialog(
                  title: Text(l.metadata_savedJobs),
                  content: SizedBox(
                      width: 640,
                      height: MediaQuery.sizeOf(context).height * .5,
                      child: Column(children: [
                        Text(l.metadata_savedJobsHelp),
                        const SizedBox(height: 12),
                        Expanded(
                            child: FutureBuilder<List<MetadataRefreshReport>>(
                                future: page,
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState !=
                                      ConnectionState.done) {
                                    return const Center(
                                        child: CircularProgressIndicator());
                                  }
                                  if (snapshot.hasError) {
                                    return Text(l.metadata_controlsError);
                                  }
                                  final jobs = snapshot.data ?? const [];
                                  if (jobs.isEmpty) {
                                    return Text(l.metadata_noSavedJobs);
                                  }
                                  return ListView(children: [
                                    for (final job in jobs)
                                      Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 8),
                                          child: _button(
                                              l.metadata_savedJobLabel(job.id,
                                                  job.state, job.requested),
                                              'metadata-saved-job-${job.id}',
                                              () => Navigator.pop(
                                                  dialogContext, job.id))),
                                    if (jobs.length == 10)
                                      _button(
                                          l.metadata_olderJobs,
                                          'metadata-older-jobs',
                                          () => update(() {
                                                page = controls.savedJobs(
                                                    beforeId: jobs.last.id);
                                              })),
                                  ]);
                                })),
                      ])),
                  actions: [
                    _button(
                        l.metadata_newestJobs,
                        'metadata-newest-jobs',
                        () => update(() {
                              page = controls.savedJobs();
                            })),
                    _button(l.common_cancel, 'metadata-saved-jobs-cancel',
                        () => Navigator.pop(dialogContext)),
                  ]);
            })));
    if (!mounted || selected == null) return;
    await controls.selectSavedJob(selected);
  }

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
                      if (widget.cacheRowId == null)
                        _button(l.metadata_savedJobs, 'metadata-saved-jobs',
                            enabled ? _selectSavedJob : null),
                      _button(
                          l.metadata_refresh,
                          'metadata-refresh',
                          enabled
                              ? () => controls.refresh(
                                  systemSlug: _scope,
                                  cacheRowId: widget.cacheRowId)
                              : null),
                      _button(l.metadata_pause, 'metadata-pause',
                          state.busy ? controls.pause : null),
                      _button(
                          l.metadata_resume,
                          'metadata-resume',
                          enabled &&
                                  report != null &&
                                  (report.state != 'completed' ||
                                      (state.artworkReport != null &&
                                          state.artworkReport!.state !=
                                              'completed'))
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
                                  ].any((s) =>
                                      (report.counts[s] ?? 0) > 0 ||
                                      (state.artworkReport?.counts[s] ?? 0) > 0)
                              ? controls.retryUnresolved
                              : null),
                    ]),
                    const SizedBox(height: 12),
                    if (widget.cacheRowId != null &&
                        widget.editionId != null) ...[
                      Text(l.metadata_rediscoverHelp),
                      const SizedBox(height: 8),
                      _button(l.metadata_rediscover, 'metadata-rediscover',
                          enabled ? _rediscover : null),
                      const SizedBox(height: 12),
                    ],
                    _button(l.metadata_openReview, 'metadata-open-review',
                        enabled ? _openReview : null),
                    if (state.busy)
                      const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: LinearProgressIndicator()),
                    if (state.error)
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                              state.sharedStorageUnavailable
                                  ? l.metadata_sharedUnavailable
                                  : l.metadata_controlsError,
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
                      MetadataProgressFeedback(report: report),
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
                    if (state.artworkReport case final artwork?) ...[
                      const SizedBox(height: 12),
                      Text(l.metadata_artwork,
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(artwork.state == 'completed'
                          ? l.metadata_jobCompleted
                          : artwork.state == 'running'
                              ? l.metadata_jobRunning
                              : l.downloadStatus_paused),
                      _coverage(l, artwork),
                      if (artwork.blockedStatus != null)
                        Text(switch (artwork.blockedStatus) {
                          'setupRequired' ||
                          'authenticationRequired' ||
                          'developerAccessRequired' =>
                            l.metadata_configureAccess,
                          'quotaExceeded' ||
                          'throttled' =>
                            l.metadata_quotaWait,
                          _ => l.metadata_offlineWait,
                        }),
                    ],
                    const SizedBox(height: 16),
                    ExpansionTile(
                        key: const ValueKey('metadata-shared-storage-section'),
                        title: Text(l.metadata_sharedStorage),
                        children: [
                          Text(l.metadata_sharedStorageHelp),
                          Text(state.sharedDirectory ??
                              l.metadata_privateStorage),
                          _button(
                              l.metadata_chooseSharedStorage,
                              'metadata-shared-storage',
                              enabled ? _selectSharedStorage : null),
                        ]),
                    _esDeSection(l, state, enabled),
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
            if (report.kind != 'artwork') l.metadata_rated: report.rated,
            l.metadata_pending: counts['pending'] ?? 0,
          }.entries)
            Text('${entry.key}: ${entry.value}'),
        ]));
  }
}
