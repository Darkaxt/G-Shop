import 'dart:io';
import 'package:path/path.dart' as p;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/input/app_intents.dart';
import '../../core/input/console_screen_mixin.dart';
import '../../core/input/global_input_wrapper.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/console_focusable.dart';
import '../../core/widgets/screen_layout.dart';
import '../../core/widgets/scroll_edge_fade.dart';
import '../../l10n/app_localizations.dart';
import '../../models/system_model.dart';
import '../../providers/metadata_providers.dart';
import '../../providers/library_providers.dart';
import '../../providers/metadata_cloud_providers.dart';
import '../../providers/app_providers.dart';
import '../../models/config/source.dart';
import '../../services/metadata/metadata_credentials.dart';
import '../../services/metadata/metadata_refresh_jobs.dart';
import '../../widgets/console_notification.dart';
import 'metadata_review_screen.dart';
import 'metadata_progress_feedback.dart';

/// All entry points share the same durable collector, never a second worker.
Future<void> openScreenScraperCollector(BuildContext context, WidgetRef ref,
        {String? systemSlug, List<String>? systemSlugs, String? scopeLabel}) =>
    _openCollector(context, ref,
        providerId: 'screenscraper',
        systemSlug: systemSlug,
        systemSlugs: systemSlugs,
        scopeLabel: scopeLabel);

Future<void> openRatingsCollector(BuildContext context, WidgetRef ref,
        {String? systemSlug, List<String>? systemSlugs}) =>
    _openCollector(context, ref,
        providerId: 'igdb',
        ratingsOnly: true,
        systemSlug: systemSlug,
        systemSlugs: systemSlugs);

Future<void> _openCollector(BuildContext context, WidgetRef ref,
    {required String providerId,
    String? systemSlug,
    List<String>? systemSlugs,
    String? scopeLabel,
    bool ratingsOnly = false}) async {
  final systems =
      systemSlugs == null ? null : List<String>.unmodifiable(systemSlugs);
  if (systems?.isEmpty == true) return;
  final controls = ref.read(metadataControlsProvider.notifier);
  if (ref.read(metadataControlsProvider).loading) await controls.load();
  if (!context.mounted) return;
  if (ref.read(metadataControlsProvider).providerId != providerId) {
    await controls.selectProvider(providerId);
  }
  if (!context.mounted) return;
  if (ref.read(metadataControlsProvider).providerId != providerId) {
    showConsoleNotification(context,
        message: 'Pause the current metadata job before switching providers.');
    return;
  }
  await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => MetadataSettingsScreen(
              systemSlug: systemSlug,
              systemSlugs: systems,
              scopeLabel: scopeLabel,
              ratingsOnly: ratingsOnly,
              openCollector: true)));
}

/// Normal settings entry, also scoped to the exact selected cached game.
class MetadataSettingsScreen extends ConsumerStatefulWidget {
  final String? systemSlug, gameTitle, editionId;
  final int? cacheRowId;
  final List<String>? systemSlugs;
  final String? scopeLabel;
  final bool openCollector;
  final bool ratingsOnly;
  const MetadataSettingsScreen(
      {super.key,
      this.systemSlug,
      this.cacheRowId,
      this.gameTitle,
      this.editionId,
      this.systemSlugs,
      this.scopeLabel,
      this.openCollector = false,
      this.ratingsOnly = false});
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
  final _sectionFocus = FocusNode(debugLabel: 'MetadataSections');
  String _section = 'provider';
  bool _scraping = false;
  bool _top25 = false;
  String? _scope;
  static const _selectedSystems = '@selected-systems';
  bool _invalid = false;
  bool _esDeClosed = false;
  String? _esDeTarget;
  @override
  String get routeId => 'metadata_settings';
  @override
  void initState() {
    super.initState();
    _scope = widget.systemSlugs == null ? widget.systemSlug : _selectedSystems;
    _scraping = widget.openCollector;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sectionFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _applicationId.dispose();
    _applicationSecret.dispose();
    _software.dispose();
    _sectionFocus.dispose();
    super.dispose();
  }

  @override
  Map<Type, Action<Intent>> get screenActions => {
        TabLeftIntent: CallbackAction<TabLeftIntent>(onInvoke: (_) {
          _cycleSection(-1);
          return null;
        }),
        TabRightIntent: CallbackAction<TabRightIntent>(onInvoke: (_) {
          _cycleSection(1);
          return null;
        }),
        BackIntent: CallbackAction<BackIntent>(onInvoke: (_) {
          _back();
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

  void _cycleSection(int delta) {
    final state = ref.read(metadataControlsProvider);
    final current = _section == 'provider' ? state.providerId : _section;
    const sections = ['screenscraper', 'igdb', 'storage', 'esde'];
    final next =
        sections[(sections.indexOf(current) + delta) % sections.length];
    if (next == 'screenscraper' || next == 'igdb') {
      if (state.busy || state.loading) return;
      _selectProvider(next);
    } else {
      setState(() => _section = next);
    }
  }

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
    final cloud = ref.read(metadataCloudProvider.notifier);
    await cloud.pause();
    try {
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
    } finally {
      cloud.resume();
    }
  }

  Widget _cloudStorage() {
    final state = ref.watch(metadataCloudProvider);
    final controller = ref.read(metadataCloudProvider.notifier);
    final sources = ref
        .watch(sourcesProvider)
        .sources
        .where((s) =>
            s.enabled &&
            s.type == SourceType.drive &&
            s.drive?.isConfigured == true)
        .toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Divider(height: 32),
      const Row(children: [
        Icon(Icons.cloud_done_outlined),
        SizedBox(width: 8),
        Text('Drive metadata library')
      ]),
      const SizedBox(height: 8),
      Text(state.message ??
          'Keep artwork in Drive, with a small local cache. Text and ratings stay offline.'),
      const SizedBox(height: 12),
      if (state.busy) const LinearProgressIndicator(),
      if (!state.enabled)
        for (final source in sources)
          _button(
              'Connect · ${source.name}',
              'metadata-cloud-connect-${source.id}',
              state.busy ? null : () => controller.connect(source)),
      if (sources.isEmpty && !state.enabled)
        const Text('Add a Google Drive source first.'),
      if (state.enabled) ...[
        const SizedBox(height: 8),
        Row(children: [
          _transportButton('Sync', 'metadata-cloud-sync', Icons.sync,
              state.busy ? null : controller.sync),
          const SizedBox(width: 8),
          _transportButton(
              'Clear cache',
              'metadata-cloud-clear',
              Icons.cleaning_services_outlined,
              state.busy ? null : controller.clearCache),
          const SizedBox(width: 8),
          _transportButton('Disconnect', 'metadata-cloud-disconnect',
              Icons.link_off, state.busy ? null : controller.disconnect),
          const SizedBox(width: 8),
          _transportButton('Rebuild media', 'metadata-cloud-rebuild',
              Icons.restart_alt, _confirmMediaRebuild),
          const SizedBox(width: 8),
          _transportButton(
              'Import artwork pack',
              'metadata-packaging-import',
              Icons.inventory_2_outlined,
              state.busy || ref.watch(metadataControlsProvider).busy
                  ? null
                  : _importPackaging),
        ]),
        const SizedBox(height: 12),
        Text(
            '${(state.cachedBytes / (1024 * 1024)).toStringAsFixed(0)} MB cached · artwork, screenshots and trailers'),
      ],
      const SizedBox(height: 8),
      Row(key: const ValueKey('metadata-cloud-budget'), children: [
        Expanded(
            child: Text(
                'Media cache · ${state.budgetBytes ~/ (1024 * 1024 * 1024)} GB')),
        _transportButton(
            'Smaller cache',
            'metadata-cloud-smaller',
            Icons.remove,
            state.busy || state.budgetBytes <= 1024 * 1024 * 1024
                ? null
                : () => controller.setBudget(state.budgetBytes ~/ 2)),
        const SizedBox(width: 8),
        _transportButton(
            'Larger cache',
            'metadata-cloud-larger',
            Icons.add,
            state.busy || state.budgetBytes >= 8 * 1024 * 1024 * 1024
                ? null
                : () => controller.setBudget(state.budgetBytes * 2)),
      ]),
    ]);
  }

  Future<void> _importPackaging() async {
    final selected = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['zip'], withData: false);
    final path = selected?.files.single.path;
    if (path == null || !mounted) return;
    final cloud = ref.read(metadataCloudProvider.notifier);
    await cloud.pause();
    try {
      final imported = await ref
          .read(metadataControlsProvider.notifier)
          .importPackagingResources(File(path));
      if (!ref.read(metadataControlsProvider).error && imported > 0) {
        ref.read(metadataMediaRevisionProvider.notifier).state++;
        ref.read(gameDbChangedProvider.notifier).state++;
        if (mounted) {
          showConsoleNotification(context,
              message: 'Artwork imported for $imported games.', isError: false);
        }
      } else if (mounted) {
        showConsoleNotification(context,
            message:
                'Artwork was not imported. Check the pack and shared storage.');
      }
    } catch (_) {
      if (mounted) {
        showConsoleNotification(context,
            message:
                'Artwork import is unavailable. Finish the current task first.');
      }
    } finally {
      cloud.resume();
      await FilePicker.platform.clearTemporaryFiles();
    }
    await cloud.sync(pull: false);
  }

  Future<void> _confirmMediaRebuild() async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Rebuild collected media?'),
              content: const Text(
                  'Remove collected images and trailers from this device '
                  'and move the old Drive exports to Trash. Game information, ROMs, '
                  'saves, settings and imported models stay. Collect media afterward '
                  'to download fresh resources.'),
              actions: [
                _button('Cancel', 'metadata-cloud-rebuild-cancel',
                    () => Navigator.pop(context, false)),
                _button('Rebuild', 'metadata-cloud-rebuild-confirm',
                    () => Navigator.pop(context, true)),
              ],
            ));
    if (confirmed == true && mounted) {
      await ref.read(metadataCloudProvider.notifier).rebuildMedia();
    }
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
    final accepted = await showConsoleDialog<bool>(
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
    return Column(
        key: const ValueKey('metadata-esde-section'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
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

  Widget _button(String label, String key, VoidCallback? onPressed,
          {bool autofocus = false}) =>
      ConsoleFocusable(
          autofocus: autofocus,
          onSelect: onPressed,
          focusScale: 1,
          child: FilledButton(
              key: ValueKey(key),
              style: AppTheme.primaryButtonStyle,
              onPressed: onPressed,
              child: Text(label)));

  Widget _transportButton(
          String label, String key, IconData icon, VoidCallback? onPressed) =>
      ConsoleFocusable(
          onSelect: onPressed,
          focusScale: 1,
          child: IconButton.filled(
              key: ValueKey(key),
              tooltip: label,
              style: AppTheme.primaryButtonStyle.copyWith(
                  fixedSize: const WidgetStatePropertyAll(Size.square(56)),
                  padding: const WidgetStatePropertyAll(EdgeInsets.all(12))),
              iconSize: 28,
              onPressed: onPressed,
              icon: Icon(icon)));

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
    final selected = await showConsoleDialog<int>(
        context: context,
        builder: (dialogContext) => ScreenActionsWrapper(
            screenActions: _dialogActions(dialogContext),
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
                        () => Navigator.pop(dialogContext),
                        autofocus: true),
                  ]);
            })));
    if (!mounted || selected == null) return;
    await controls.selectSavedJob(selected);
  }

  void _back() {
    if (_section == 'provider' && _scraping) {
      setState(() => _scraping = false);
    } else {
      Navigator.maybePop(context);
    }
  }

  Map<Type, Action<Intent>> _dialogActions(BuildContext dialogContext) => {
        for (final action in screenActions.entries)
          if (action.key != TabLeftIntent && action.key != TabRightIntent)
            action.key: action.value,
        BackIntent: CallbackAction<BackIntent>(onInvoke: (_) {
          Navigator.pop(dialogContext);
          return null;
        }),
      };

  Future<void> _selectProvider(String id) async {
    final controls = ref.read(metadataControlsProvider.notifier);
    if (ref.read(metadataControlsProvider).providerId != id) {
      _clearFields();
      await controls.selectProvider(id);
    }
    if (!mounted) return;
    setState(() {
      _section = 'provider';
      _scraping = false;
      _invalid = false;
    });
  }

  Future<void> _editCredentials() async {
    _clearFields();
    _invalid = false;
    final l = L.of(context);
    await showConsoleDialog<void>(
      context: context,
      builder: (dialogContext) => ScreenActionsWrapper(
        screenActions: _dialogActions(dialogContext),
        child: StatefulBuilder(
            builder: (context, update) => Consumer(
                  builder: (context, ref, _) {
                    final state = ref.watch(metadataControlsProvider);
                    final controls =
                        ref.read(metadataControlsProvider.notifier);
                    final enabled = !state.busy && !state.loading;
                    final ss = state.providerId == 'screenscraper';
                    return AlertDialog(
                      title: Text(
                          '${ss ? 'ScreenScraper' : 'IGDB'} · ${l.metadata_credentials}'),
                      content: SizedBox(
                        width: 640,
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(l.metadata_accessInfo),
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
                                      _field(
                                          _applicationId,
                                          l.metadata_clientId,
                                          'metadata-client-id',
                                          enabled: enabled),
                                      _field(
                                          _applicationSecret,
                                          l.metadata_clientSecret,
                                          'metadata-client-secret',
                                          secret: true,
                                          enabled: enabled),
                                      _field(_software, l.metadata_softwareName,
                                          'metadata-software',
                                          enabled: enabled),
                                    ])
                              else ...[
                                _field(_applicationId, l.metadata_clientId,
                                    'metadata-client-id',
                                    enabled: enabled),
                                _field(
                                    _applicationSecret,
                                    l.metadata_clientSecret,
                                    'metadata-client-secret',
                                    secret: true,
                                    enabled: enabled),
                              ],
                              if (_invalid)
                                Text(l.metadata_invalidInput,
                                    style:
                                        const TextStyle(color: Colors.amber)),
                              Wrap(spacing: 12, runSpacing: 8, children: [
                                _button(
                                    l.common_save,
                                    'metadata-save',
                                    enabled
                                        ? () async {
                                            await _save();
                                            if (!mounted ||
                                                !dialogContext.mounted) {
                                              return;
                                            }
                                            if (!_invalid &&
                                                !ref
                                                    .read(
                                                        metadataControlsProvider)
                                                    .error) {
                                              Navigator.pop(dialogContext);
                                            } else {
                                              update(() {});
                                            }
                                          }
                                        : null),
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
                              if (state.error)
                                Text(l.metadata_controlsError,
                                    style:
                                        const TextStyle(color: Colors.amber)),
                            ],
                          ),
                        ),
                      ),
                      actions: [
                        _button(l.common_cancel, 'metadata-credentials-cancel',
                            enabled ? () => Navigator.pop(dialogContext) : null,
                            autofocus: true),
                      ],
                    );
                  },
                )),
      ),
    );
    _clearFields();
    _invalid = false;
  }

  Widget _navigationItem(String label, String key, IconData icon, bool selected,
          VoidCallback? onPressed,
          {FocusNode? focusNode}) =>
      Semantics(
        selected: selected,
        child: ConsoleFocusable(
          focusNode: focusNode,
          onSelect: onPressed,
          focusScale: 1,
          child: TextButton.icon(
            key: ValueKey(key),
            style: TextButton.styleFrom(
              alignment: Alignment.centerLeft,
              minimumSize: const Size.fromHeight(56),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              foregroundColor: selected ? Colors.white : Colors.white70,
              backgroundColor: selected
                  ? AppTheme.primaryColor.withValues(alpha: .18)
                  : Colors.transparent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: onPressed,
            icon: Icon(icon, size: 22),
            label: Text(label),
          ),
        ),
      );

  Widget _scrapingWorkspace(L l, MetadataControlsState state, bool enabled) {
    final controls = ref.read(metadataControlsProvider.notifier);
    final report = state.report;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (widget.ratingsOnly && state.providerId == 'igdb') ...[
        const Text('Refresh ratings without downloading ROMs or artwork.'),
        const SizedBox(height: 12),
      ],
      if (widget.cacheRowId != null)
        Text(
            '${l.metadata_gameScope}: ${widget.gameTitle ?? widget.cacheRowId}')
      else
        DropdownButtonFormField<String>(
            key: const ValueKey('metadata-scope'),
            isExpanded: true,
            initialValue: _scope ?? '',
            decoration: InputDecoration(labelText: l.metadata_systemScope),
            items: [
              DropdownMenuItem(
                  value: '',
                  child: Text(l.metadata_fullScope,
                      overflow: TextOverflow.ellipsis)),
              if (widget.systemSlugs != null)
                DropdownMenuItem(
                    value: _selectedSystems,
                    child: Text(widget.scopeLabel ?? 'Selected consoles',
                        overflow: TextOverflow.ellipsis)),
              for (final system in {
                ...state.systems,
                if (_scope != null && _scope != _selectedSystems) _scope!
              })
                DropdownMenuItem(
                    value: system,
                    child: Text(system, overflow: TextOverflow.ellipsis))
            ],
            onChanged: enabled
                ? (value) => setState(() => _scope = value == '' ? null : value)
                : null),
      const SizedBox(height: 12),
      Wrap(spacing: 12, runSpacing: 8, children: [
        if (widget.cacheRowId == null &&
            !widget.ratingsOnly &&
            state.providerId == 'screenscraper')
          SegmentedButton<bool>(
              key: const ValueKey('metadata-top25'),
              segments: const [
                ButtonSegment(
                    value: false,
                    label: Text('All games'),
                    icon: Icon(Icons.apps)),
                ButtonSegment(
                    value: true,
                    label: Text('Top 25 per console'),
                    icon: Icon(Icons.star_outline))
              ],
              selected: {_top25},
              onSelectionChanged: enabled
                  ? (values) => setState(() => _top25 = values.single)
                  : null),
        if (widget.cacheRowId == null)
          _button(l.metadata_savedJobs, 'metadata-saved-jobs',
              enabled ? _selectSavedJob : null),
        if (widget.cacheRowId == null && state.providerId == 'screenscraper')
          _transportButton(
              'Collect media',
              'metadata-collect-resources',
              Icons.perm_media_outlined,
              enabled
                  ? () => controls.collectResources(
                      top25PerSystem: _top25,
                      systemSlug: _scope == _selectedSystems ? null : _scope,
                      systemSlugs: _scope == _selectedSystems
                          ? widget.systemSlugs
                          : null)
                  : null),
        _transportButton(
            l.metadata_refresh,
            'metadata-refresh',
            Icons.play_circle_outline,
            enabled
                ? () => controls.refresh(
                    systemSlug: _scope == _selectedSystems ? null : _scope,
                    systemSlugs:
                        _scope == _selectedSystems ? widget.systemSlugs : null,
                    ratingsOnly:
                        widget.ratingsOnly && state.providerId == 'igdb',
                    top25PerSystem: _top25 &&
                        !widget.ratingsOnly &&
                        state.providerId == 'screenscraper',
                    cacheRowId: widget.cacheRowId)
                : null),
        _transportButton(l.metadata_pause, 'metadata-pause',
            Icons.pause_rounded, state.busy ? controls.pause : null),
        _transportButton(
            l.metadata_resume,
            'metadata-resume',
            Icons.play_arrow_rounded,
            enabled &&
                    report != null &&
                    (report.state != 'completed' ||
                        (state.artworkReport != null &&
                            state.artworkReport!.state != 'completed'))
                ? controls.resume
                : null),
        _transportButton(
            l.metadata_retryOutcomes,
            'metadata-retry',
            Icons.replay_rounded,
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
      if (widget.cacheRowId != null && widget.editionId != null) ...[
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
        _button(
            l.common_retry, 'metadata-reload', enabled ? controls.load : null),
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
        if (report.top25PerSystem)
          ExpansionTile(
              title: const Text('Top 25 selection'),
              subtitle: const Text('Original selection · selected / ranked'),
              children: [
                for (final entry in report.selectionCoverage.entries)
                  ListTile(
                      dense: true,
                      title: Text(SystemModel.supportedSystems
                              .where((system) => system.id == entry.key)
                              .firstOrNull
                              ?.name ??
                          entry.key),
                      trailing: Text(
                          '${entry.value['selected']} / ${entry.value['eligible']}'),
                      subtitle: Text(
                          '${entry.value['collection']} games in collection'))
              ]),
        MetadataProgressFeedback(report: report),
        if (report.blockedStatus != null)
          Text(switch (report.blockedStatus) {
            'setupRequired' ||
            'authenticationRequired' ||
            'developerAccessRequired' =>
              l.metadata_configureAccess,
            'quotaExceeded' || 'throttled' => l.metadata_quotaWait,
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
            'quotaExceeded' || 'throttled' => l.metadata_quotaWait,
            _ => l.metadata_offlineWait,
          }),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final state = ref.watch(metadataControlsProvider);
    final controls = ref.read(metadataControlsProvider.notifier);
    final enabled = !state.busy && !state.loading;
    final provider =
        state.providerId == 'screenscraper' ? 'ScreenScraper' : 'IGDB';
    final title = switch (_section) {
      'storage' => l.metadata_sharedStorage,
      'esde' => l.metadata_esDe,
      _ => _scraping ? '$provider · ${l.metadata_scraping}' : provider,
    };
    return buildWithActions(
      PopScope(
        canPop: !(_section == 'provider' && _scraping),
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _back();
        },
        child: ScreenLayout(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Row(children: [
                IconButton(
                  key: const ValueKey('metadata-back'),
                  tooltip: l.common_back,
                  onPressed: _back,
                  icon: const Icon(Icons.arrow_back),
                ),
                Expanded(
                    child: Text(l.metadata_setupTitle,
                        style: Theme.of(context).textTheme.headlineSmall)),
              ]),
              const SizedBox(height: 12),
              Expanded(child: LayoutBuilder(builder: (context, constraints) {
                final compact = constraints.maxWidth < 700;
                return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: compact ? 144 : 244,
                        child: FocusTraversalGroup(
                          child: ListView(
                            key: const ValueKey('metadata-navigation'),
                            children: [
                              _navigationItem(
                                  'ScreenScraper',
                                  'metadata-nav-screenscraper',
                                  Icons.travel_explore,
                                  _section == 'provider' &&
                                      state.providerId == 'screenscraper',
                                  enabled || state.providerId == 'screenscraper'
                                      ? () => _selectProvider('screenscraper')
                                      : null,
                                  focusNode: _sectionFocus),
                              const SizedBox(height: 8),
                              _navigationItem(
                                  'IGDB',
                                  'metadata-nav-igdb',
                                  Icons.games_outlined,
                                  _section == 'provider' &&
                                      state.providerId == 'igdb',
                                  enabled || state.providerId == 'igdb'
                                      ? () => _selectProvider('igdb')
                                      : null),
                              const Divider(height: 28),
                              _navigationItem(
                                  l.metadata_sharedStorage,
                                  'metadata-nav-storage',
                                  Icons.folder_outlined,
                                  _section == 'storage',
                                  () => setState(() => _section = 'storage')),
                              const SizedBox(height: 8),
                              _navigationItem(
                                  l.metadata_esDe,
                                  'metadata-nav-esde',
                                  Icons.publish_outlined,
                                  _section == 'esde',
                                  () => setState(() => _section = 'esde')),
                            ],
                          ),
                        ),
                      ),
                      const VerticalDivider(width: 24),
                      Expanded(
                          child: FocusTraversalGroup(
                        child: ScrollEdgeFade(
                            child: ListView(
                          key: ValueKey(
                              'metadata-content-$_section-$_scraping-${state.providerId}'),
                          padding: EdgeInsets.only(
                              right: compact ? 0 : 16, bottom: 24),
                          children: [
                            Text(title,
                                style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: 16),
                            if (state.loading) const LinearProgressIndicator(),
                            if (state.error &&
                                !(_section == 'provider' && _scraping)) ...[
                              Text(
                                  state.sharedStorageUnavailable
                                      ? l.metadata_sharedUnavailable
                                      : l.metadata_controlsError,
                                  style: const TextStyle(color: Colors.amber)),
                              if (state.report == null)
                                _button(l.common_retry, 'metadata-reload',
                                    enabled ? controls.load : null),
                              const SizedBox(height: 12),
                            ],
                            if (_section == 'storage')
                              Column(
                                key: const ValueKey(
                                    'metadata-shared-storage-section'),
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(l.metadata_sharedStorageHelp),
                                  const SizedBox(height: 16),
                                  Text(state.sharedDirectory ??
                                      l.metadata_privateStorage),
                                  const SizedBox(height: 16),
                                  _button(
                                      l.metadata_chooseSharedStorage,
                                      'metadata-shared-storage',
                                      enabled ? _selectSharedStorage : null),
                                  _cloudStorage(),
                                ],
                              )
                            else if (_section == 'esde')
                              _esDeSection(l, state, enabled)
                            else if (_scraping)
                              _scrapingWorkspace(l, state, enabled)
                            else ...[
                              Text(l.metadata_setupSubtitle),
                              const SizedBox(height: 20),
                              if (state.providerId == 'screenscraper')
                                Text(
                                    '${l.providerForm_username}: ${state.accountConfigured ? l.metadata_saved : l.metadata_notConfigured}'),
                              Text(
                                  '${l.metadata_applicationAccess}: ${state.applicationConfigured ? l.metadata_saved : l.metadata_notConfigured}'),
                              const SizedBox(height: 20),
                              Wrap(spacing: 12, runSpacing: 12, children: [
                                _button(
                                    l.metadata_credentials,
                                    'metadata-credentials',
                                    enabled ? _editCredentials : null),
                                _button(
                                    l.metadata_scraping,
                                    'metadata-open-scraping',
                                    () => setState(() => _scraping = true)),
                              ]),
                              if (state.report case final report?) ...[
                                const SizedBox(height: 20),
                                Text(l.metadata_savedJobLabel(
                                    report.id, report.state, report.requested)),
                                if (state.busy) const LinearProgressIndicator(),
                              ],
                            ],
                          ],
                        )),
                      )),
                    ]);
              })),
            ]),
          ),
        ),
      ),
      localFocusScope: true,
    );
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
