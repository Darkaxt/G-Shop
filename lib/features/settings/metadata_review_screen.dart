import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/input/app_intents.dart';
import '../../core/input/console_screen_mixin.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/console_focusable.dart';
import '../../core/widgets/screen_layout.dart';
import '../../l10n/app_localizations.dart';
import '../../models/library_identity.dart';
import '../../providers/metadata_providers.dart';
import '../../services/metadata/metadata_refresh_jobs.dart';

/// Bounded local outcomes in the normal metadata workflow, not a new catalogue.
class MetadataReviewScreen extends ConsumerStatefulWidget {
  final String? systemSlug, editionId;
  final int? cacheRowId;
  const MetadataReviewScreen(
      {super.key, this.systemSlug, this.editionId, this.cacheRowId});
  @override
  ConsumerState<MetadataReviewScreen> createState() =>
      _MetadataReviewScreenState();
}

class _MetadataReviewScreenState extends ConsumerState<MetadataReviewScreen>
    with ConsoleScreenMixin {
  static const _pageSize = 20;
  List<MetadataReviewItem> _items = const [];
  final _previous = <String>[];
  String _cursor = '';
  bool _loading = true, _error = false, _hasNext = false, _saved = false;
  @override
  String get routeId => 'metadata_review';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final items = await ref
          .read(metadataControlsProvider.notifier)
          .reviewQueue(
              afterEditionId: _cursor,
              limit: _pageSize + 1,
              systemSlug: widget.systemSlug,
              editionId: widget.editionId,
              cacheRowId: widget.cacheRowId);
      if (!mounted) return;
      setState(() {
        _items = List.unmodifiable(items.take(_pageSize));
        _hasNext = items.length > _pageSize;
      });
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _accept(MetadataReviewItem item, String id, Set<String> tags,
      String? region) async {
    final controls = ref.read(metadataControlsProvider.notifier);
    await controls.acceptReview(item,
        providerGameId: id, contentTags: tags, reviewedRegion: region);
    if (!mounted) return;
    setState(() => _saved = !ref.read(metadataControlsProvider).error);
    await _load();
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
          FocusManager.instance.primaryFocus
              ?.focusInDirection(switch (intent.direction) {
            GridDirection.up => TraversalDirection.up,
            GridDirection.down => TraversalDirection.down,
            GridDirection.left => TraversalDirection.left,
            GridDirection.right => TraversalDirection.right,
          });
          return null;
        }),
      };

  Widget _button(String label, String key, VoidCallback? action) =>
      ConsoleFocusable(
          onSelect: action,
          focusScale: 1,
          child: FilledButton(
              key: ValueKey(key),
              style: AppTheme.primaryButtonStyle,
              onPressed: action,
              child: Text(label)));

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final state = ref.watch(metadataControlsProvider);
    final controls = ref.read(metadataControlsProvider.notifier);
    final enabled = !_loading && !state.busy && !state.loading;
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
                  child: Text(l.metadata_reviewTitle,
                      style: Theme.of(context).textTheme.headlineSmall)),
            ]),
            Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 880),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                              '${state.providerId == 'igdb' ? 'IGDB' : 'ScreenScraper'} · '
                              '${widget.editionId != null || widget.cacheRowId != null ? l.metadata_gameScope : widget.systemSlug ?? l.metadata_fullScope}'),
                          const SizedBox(height: 12),
                          Text(l.metadata_reviewInfo),
                          const SizedBox(height: 12),
                          Wrap(spacing: 12, runSpacing: 8, children: [
                            _button(
                                l.metadata_reviewReload,
                                'review-reload',
                                enabled
                                    ? () {
                                        _cursor = '';
                                        _previous.clear();
                                        _load();
                                      }
                                    : null),
                            _button(
                                l.metadata_reviewPrevious,
                                'review-previous',
                                enabled && _previous.isNotEmpty
                                    ? () {
                                        _cursor = _previous.removeLast();
                                        _load();
                                      }
                                    : null),
                            _button(
                                l.metadata_reviewNext,
                                'review-next',
                                enabled && _hasNext
                                    ? () {
                                        _previous.add(_cursor);
                                        _cursor = _items.last.editionId;
                                        _load();
                                      }
                                    : null),
                          ]),
                          if (_loading || state.busy)
                            const LinearProgressIndicator(),
                          if (_error || state.error) ...[
                            const SizedBox(height: 12),
                            Text(l.metadata_reviewError,
                                style: const TextStyle(color: Colors.amber)),
                          ],
                          if (_saved) ...[
                            const SizedBox(height: 12),
                            Text(l.metadata_reviewSaved),
                          ],
                          if (state.report != null &&
                              (_saved || state.busy || state.error)) ...[
                            const SizedBox(height: 12),
                            Text(
                                '${l.metadata_matched}: ${state.report!.counts['matched'] ?? 0} · '
                                '${l.metadata_pending}: ${state.report!.counts['pending'] ?? 0}'),
                            Wrap(spacing: 12, runSpacing: 8, children: [
                              _button(l.metadata_pause, 'review-pause',
                                  state.busy ? controls.pause : null),
                              _button(
                                  l.metadata_resume,
                                  'review-resume',
                                  enabled && state.report!.state != 'completed'
                                      ? controls.resume
                                      : null),
                            ]),
                            Text(l.metadata_completeNote),
                          ],
                          if (!_loading && !_error && _items.isEmpty) ...[
                            const SizedBox(height: 24),
                            Text(l.metadata_reviewEmpty),
                          ],
                          for (final item in _items)
                            _ReviewCard(
                                key:
                                    ValueKey('${item.jobId}:${item.editionId}'),
                                item: item,
                                enabled: enabled && item.identityCurrent,
                                onAccept: (id, tags, region) =>
                                    _accept(item, id, tags, region)),
                        ]))),
          ]),
        )),
        localFocusScope: true);
  }
}

class _ReviewCard extends StatefulWidget {
  final MetadataReviewItem item;
  final bool enabled;
  final void Function(String id, Set<String> tags, String? region) onAccept;
  const _ReviewCard(
      {super.key,
      required this.item,
      required this.enabled,
      required this.onAccept});
  @override
  State<_ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends State<_ReviewCard> {
  int? _candidate;
  // Null preserves existing release evidence. An explicitly cleared field
  // records Unknown; neither the filename nor a game-ID choice supplies it.
  String? _reviewedRegion;
  late final Set<String> _tags = {
    ...widget.item.request?.contentTags ?? <String>{}
  }..retainAll(EditionIdentity.knownContentTags);

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final item = widget.item;
    final request = item.request;
    final candidates = item.candidates;
    final selected = _candidate == null ? null : candidates[_candidate!];
    final validTags =
        _tags.isNotEmpty && (!_tags.contains('official') || _tags.length == 1);
    return Card(
        margin: const EdgeInsets.only(top: 20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(request?.title ?? item.editionId,
                style: Theme.of(context).textTheme.titleLarge),
            for (final label in item.artifactLabels)
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            Text([
              request?.platformId,
              request?.region,
              request?.language,
              request?.revision
            ].whereType<String>().join(' · ')),
            Text(item.status == 'ambiguous'
                ? l.metadata_ambiguous
                : item.status == 'unmatched'
                    ? l.metadata_unmatched
                    : l.metadata_review),
            if (!item.identityCurrent)
              Text(l.metadata_reviewChanged,
                  style: const TextStyle(color: Colors.amber)),
            const SizedBox(height: 12),
            if (candidates.isEmpty)
              Text(l.metadata_noCandidates)
            else ...[
              DropdownButtonFormField<int>(
                  key: ValueKey('review-candidate-${item.editionId}'),
                  isExpanded: true,
                  decoration:
                      InputDecoration(labelText: l.metadata_chooseCandidate),
                  items: [
                    for (var i = 0; i < candidates.length; i++)
                      DropdownMenuItem(
                          value: i,
                          enabled: candidates[i].platformId ==
                                  request?.platformId &&
                              candidates
                                      .where((c) =>
                                          c.providerGameId ==
                                              candidates[i].providerGameId &&
                                          c.platformId == request?.platformId)
                                      .length ==
                                  1,
                          child: Text(
                              '${candidates[i].titles.map((t) => t.text).join(' / ')} · '
                              '${candidates[i].platformId} · #${candidates[i].providerGameId}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: widget.enabled
                      ? (value) => setState(() => _candidate = value)
                      : null),
              if (selected != null)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                        '${l.metadata_candidateEvidence}: ${selected.evidence}')),
              const SizedBox(height: 16),
              TextFormField(
                  key: ValueKey('review-region-${item.editionId}'),
                  initialValue: request?.region ?? '',
                  enabled: widget.enabled,
                  maxLength: 32,
                  decoration: InputDecoration(
                      labelText: l.filter_regions, hintText: l.filter_unknown),
                  onChanged: (value) => _reviewedRegion = value.trim()),
              const SizedBox(height: 16),
              Text(l.filter_contentTags),
              Wrap(spacing: 8, runSpacing: 4, children: [
                for (final tag in EditionIdentity.knownContentTags)
                  FilterChip(
                      key: ValueKey('review-tag-${item.editionId}-$tag'),
                      label: Text(switch (tag) {
                        'official' => l.filter_official,
                        'unknown' => l.filter_unknown,
                        'homebrew' => l.filter_homebrew,
                        'demo' => l.filter_demo,
                        _ => tag,
                      }),
                      selected: _tags.contains(tag),
                      onSelected: widget.enabled
                          ? (checked) => setState(() {
                                if (checked) {
                                  if (tag == 'official') {
                                    _tags.clear();
                                  } else {
                                    _tags.remove('official');
                                  }
                                  _tags.add(tag);
                                } else {
                                  _tags.remove(tag);
                                }
                              })
                          : null),
              ]),
              const SizedBox(height: 12),
              ConsoleFocusable(
                  focusScale: 1,
                  onSelect: widget.enabled && selected != null && validTags
                      ? () => widget.onAccept(selected.providerGameId,
                          Set.of(_tags), _reviewedRegion)
                      : null,
                  child: FilledButton(
                      key: ValueKey('review-accept-${item.editionId}'),
                      style: AppTheme.primaryButtonStyle,
                      onPressed: widget.enabled && selected != null && validTags
                          ? () => widget.onAccept(selected.providerGameId,
                              Set.of(_tags), _reviewedRegion)
                          : null,
                      child: Text(l.metadata_reviewAccept))),
            ],
          ]),
        ));
  }
}
