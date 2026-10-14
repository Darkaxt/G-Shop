import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/input/input.dart';
import '../../core/theme/app_theme.dart';
import '../../models/rom_cache_policy.dart';
import '../../providers/rom_cache_providers.dart';
import '../../services/rom_cache_runtime.dart';

enum _CacheSection { policy, consoles, games, status }

class RomCacheSettingsScreen extends ConsumerStatefulWidget {
  final RomCacheRuntime? runtime;
  const RomCacheSettingsScreen({super.key, this.runtime});
  @override
  ConsumerState<RomCacheSettingsScreen> createState() =>
      _RomCacheSettingsState();
}

class _RomCacheSettingsState extends ConsumerState<RomCacheSettingsScreen>
    with ConsoleScreenMixin {
  @override
  String get routeId => 'rom-cache-settings';
  _CacheSection _section = _CacheSection.policy;
  RomCacheRuntime? _runtime;
  RomCachePolicy? _draft;
  final _consoles = <String, String>{};
  String? _console, _problem;
  bool _dirty = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final provided = widget.runtime;
      final RomCacheRuntime runtime;
      if (provided != null) {
        runtime = provided;
      } else {
        runtime = await ref.read(romCacheProvider.future);
      }
      final config = await runtime.configuration();
      await runtime.snapshot(preview: true);
      if (!mounted) return;
      _runtime = runtime;
      _consoles.addEntries(config.systems.map((s) => MapEntry(s.id, s.name)));
      _console = _consoles.keys.firstOrNull;
      _draft = runtime.latest!.policy;
      runtime.addListener(_changed);
      setState(() {});
    } catch (_) {
      if (mounted) {
        setState(() => _problem = 'Could not load ROM cache settings.');
      }
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _runtime?.removeListener(_changed);
    super.dispose();
  }

  @override
  Map<Type, Action<Intent>> get screenActions => {
        BackIntent: CallbackAction<BackIntent>(onInvoke: (_) {
          Navigator.maybePop(context);
          return null;
        }),
        ConfirmIntent: CallbackAction<ConfirmIntent>(onInvoke: (_) {
          final target = FocusManager.instance.primaryFocus?.context;
          if (target != null) {
            Actions.maybeInvoke(target, const ActivateIntent());
          }
          return null;
        }),
        NavigateIntent: CallbackAction<NavigateIntent>(onInvoke: (intent) {
          if (FocusManager.instance.primaryFocus?.context?.widget
              is EditableText) {
            return null;
          }
          final focus = FocusManager.instance.primaryFocus;
          if (focus == null || focus == screenFocusNode) {
            screenFocusNode.nextFocus();
            return null;
          }
          FocusManager.instance.primaryFocus
              ?.focusInDirection(switch (intent.direction) {
            GridDirection.up => TraversalDirection.up,
            GridDirection.down => TraversalDirection.down,
            GridDirection.left => TraversalDirection.left,
            GridDirection.right => TraversalDirection.right
          });
          return null;
        }),
      };
  String _bytes(int value) => value < 1024 * 1024
      ? '${(value / 1024).toStringAsFixed(0)} KiB'
      : value < 1024 * 1024 * 1024
          ? '${(value / 1024 / 1024).toStringAsFixed(1)} MiB'
          : '${(value / 1024 / 1024 / 1024).toStringAsFixed(1)} GiB';
  String _reason(String value) => switch (value) {
        'expired' => 'Retention expired',
        'game_limit' => 'Game limit',
        'byte_limit' => 'Storage limit',
        'in_use' => 'Game is in use',
        'clock_changed' => 'Device clock needs review',
        'unknown_usage' => 'Use history is unknown',
        'source_unavailable' => 'Drive source unavailable',
        'restore_unproved' => 'Restore format needs verification',
        'transfer_active' => 'Transfer still active',
        'removal_pending' => 'Cleanup recovery pending',
        'identity_unresolved' => 'Game identity needs review',
        'location_changed' => 'ROM folder changed',
        'cancelled' => 'Stopped',
        'cloud_unavailable' => 'Cloud copy could not be verified',
        _ => 'File needs review',
      };
  void _setField(String key, int? value, {bool inherit = false}) {
    final draft = _draft!;
    setState(() {
      if (_section == _CacheSection.consoles && _console != null) {
        final overrides = {
          for (final entry in draft.consoles.entries)
            entry.key: {...entry.value}
        };
        final fields = overrides.putIfAbsent(_console!, () => {});
        if (inherit) {
          fields.remove(key);
        } else {
          fields[key] = value;
        }
        if (fields.isEmpty) overrides.remove(_console);
        _draft = draft.copyWith(consoles: overrides);
      } else {
        _draft = draft.copyWith(
            defaults: RomCacheLimits.decode(
                {...draft.defaults.toJson(), key: value}));
      }
      _dirty = true;
    });
  }

  Future<void> _number(String title, String field,
      {bool days = false, bool gib = false}) async {
    final scoped = _section == _CacheSection.consoles && _console != null;
    final limits = scoped
        ? _draft!.copyWith(scope: RomCacheScope.perConsole).limitsFor(_console!)
        : _draft!.defaults;
    final raw = limits.toJson()[field];
    final divisor = days
        ? const Duration(days: 1).inMilliseconds
        : gib
            ? 1024 * 1024 * 1024
            : 1;
    var currentText = raw == null ? '' : (raw / divisor).toString();
    String? error;
    final value = await showDialog<({bool inherit, int? value})>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
                    title: Text(title),
                    content: SizedBox(
                        width: 320,
                        child: TextFormField(
                            key: ValueKey('cache-value-$field'),
                            initialValue: currentText,
                            onChanged: (value) => currentText = value,
                            autofocus: true,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: InputDecoration(
                                labelText: days
                                    ? 'Days'
                                    : gib
                                        ? 'GiB'
                                        : 'Games',
                                hintText: days ? 'Never' : 'No limit',
                                errorText: error))),
                    actions: [
                      if (scoped)
                        TextButton(
                            onPressed: () => Navigator.pop(
                                context, (inherit: true, value: null)),
                            child: const Text('Inherit')),
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel')),
                      FilledButton(
                          style: AppTheme.primaryButtonStyle,
                          onPressed: () {
                            final text = currentText.trim();
                            final number = double.tryParse(text);
                            if (text.isNotEmpty &&
                                (number == null ||
                                    !number.isFinite ||
                                    number < 0 ||
                                    !days &&
                                        !gib &&
                                        number != number.roundToDouble())) {
                              update(() => error =
                                  'Enter a positive number, zero, or leave blank.');
                              return;
                            }
                            Navigator.pop(context, (
                              inherit: false,
                              value: number == null
                                  ? null
                                  : (number * divisor).round()
                            ));
                          },
                          child: const Text('Save')),
                    ])));
    if (value != null && mounted) {
      _setField(field, value.value, inherit: value.inherit);
    }
  }

  Widget _limits({required bool scoped}) {
    final draft = _draft!;
    if (scoped && _console == null) {
      return const Text('Add a console source first.');
    }
    final limits = scoped
        ? draft.copyWith(scope: RomCacheScope.perConsole).limitsFor(_console!)
        : draft.defaults;
    final override = scoped ? draft.consoles[_console] : null;
    String inherited(String field, String label) =>
        scoped && override?.containsKey(field) != true
            ? 'Inherited · $label'
            : label;
    final duration = limits.keepFor == null
        ? 'Never'
        : '${(limits.keepFor!.inMilliseconds / const Duration(days: 1).inMilliseconds).toStringAsFixed(2)} days';
    final busy = _runtime!.busy;
    return Column(children: [
      ListTile(
          key: const ValueKey('cache-retention'),
          leading: const Icon(Icons.schedule_outlined),
          title: const Text('Keep after last use'),
          subtitle: Text(inherited('keepMilliseconds', duration)),
          trailing: const Icon(Icons.edit_outlined),
          enabled: !busy,
          onTap: () =>
              _number('Retention window', 'keepMilliseconds', days: true)),
      ListTile(
          key: const ValueKey('cache-game-limit'),
          leading: const Icon(Icons.queue_outlined),
          title: const Text('Rotation queue'),
          subtitle: Text(inherited(
              'maxGames',
              limits.maxGames == null
                  ? 'No game limit'
                  : '${limits.maxGames} unpinned games')),
          trailing: const Icon(Icons.edit_outlined),
          enabled: !busy,
          onTap: () => _number('Game limit', 'maxGames')),
      ListTile(
          key: const ValueKey('cache-byte-limit'),
          leading: const Icon(Icons.storage_outlined),
          title: const Text('Storage budget'),
          subtitle: Text(inherited(
              'maxBytes',
              limits.maxBytes == null
                  ? 'No storage limit'
                  : _bytes(limits.maxBytes!))),
          trailing: const Icon(Icons.edit_outlined),
          enabled: !busy,
          onTap: () => _number('Storage budget', 'maxBytes', gib: true)),
      if (scoped)
        Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
                onPressed: busy
                    ? null
                    : () {
                        setState(() {
                          _draft = draft.copyWith(
                              consoles: {...draft.consoles}..remove(_console));
                          _dirty = true;
                        });
                      },
                icon: const Icon(Icons.restart_alt),
                label: const Text('Use defaults'))),
    ]);
  }

  Future<void> _apply() async {
    final draft = _draft!;
    try {
      await _runtime!.updatePolicy(draft);
      if (mounted) setState(() => _dirty = false);
    } catch (_) {
      if (mounted) setState(() => _problem = 'Could not save cache settings.');
    }
  }

  Widget _body(RomCachePlan plan) {
    final runtime = _runtime!, draft = _draft!;
    final games = runtime.latest!.games;
    if (_section == _CacheSection.policy) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SwitchListTile(
            key: const ValueKey('cache-enabled'),
            title: const Text('Automatic cleanup'),
            subtitle: const Text(
                'Only verified cloud-backed, managed ROMs are removed.'),
            value: draft.enabled,
            onChanged: runtime.busy
                ? null
                : (value) => setState(() {
                      _draft = draft.copyWith(enabled: value);
                      _dirty = true;
                    })),
        DropdownButtonFormField<RomCacheScope>(
            key: const ValueKey('cache-scope'),
            initialValue: draft.scope,
            decoration: const InputDecoration(labelText: 'Pool'),
            items: const [
              DropdownMenuItem(
                  value: RomCacheScope.unified, child: Text('Unified')),
              DropdownMenuItem(
                  value: RomCacheScope.perConsole, child: Text('Per console'))
            ],
            onChanged: runtime.busy
                ? null
                : (value) {
                    if (value != null) {
                      setState(() {
                        _draft = draft.copyWith(scope: value);
                        _dirty = true;
                      });
                    }
                  }),
        const SizedBox(height: 12),
        DropdownButtonFormField<RomCacheOrder>(
            key: const ValueKey('cache-order'),
            initialValue: draft.order,
            decoration: const InputDecoration(labelText: 'Rotation order'),
            items: const [
              DropdownMenuItem(
                  value: RomCacheOrder.lru, child: Text('Least recently used')),
              DropdownMenuItem(
                  value: RomCacheOrder.fifo, child: Text('First installed'))
            ],
            onChanged: runtime.busy
                ? null
                : (value) {
                    if (value != null) {
                      setState(() {
                        _draft = draft.copyWith(order: value);
                        _dirty = true;
                      });
                    }
                  }),
        const SizedBox(height: 12),
        _limits(scoped: false),
        const Text(
            'Never disables age cleanup. Game and storage limits can still rotate ROMs. '
            'Use is recorded only after a successful launch through R-Shop.'),
      ]);
    }
    if (_section == _CacheSection.consoles) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        DropdownButtonFormField<String>(
            key: ValueKey('cache-console-$_console'),
            initialValue: _console,
            decoration: const InputDecoration(labelText: 'Console'),
            items: [
              for (final entry in _consoles.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value))
            ],
            onChanged: runtime.busy
                ? null
                : (value) => setState(() => _console = value)),
        const SizedBox(height: 12),
        if (draft.scope == RomCacheScope.unified)
          const Text(
              'These overrides are saved, but Unified uses the default limits.'),
        _limits(scoped: true),
      ]);
    }
    if (_section == _CacheSection.games) {
      return Column(children: [
        const Text(
            'Top-25 offline games stay protected. Pins apply across re-downloads.'),
        DropdownButtonFormField<String>(
            key: const ValueKey('cache-games-console'),
            initialValue: _console,
            decoration: const InputDecoration(labelText: 'Console'),
            items: [
              for (final entry in _consoles.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value))
            ],
            onChanged: (value) => setState(() => _console = value)),
        for (final game in games.where((g) => g.entry.platform == _console))
          ListTile(
              key: ValueKey('cache-game-${game.entry.id}'),
              leading: Icon(game.entry.offlineSample
                  ? Icons.shield_outlined
                  : game.entry.pinned
                      ? Icons.push_pin
                      : Icons.sd_card_outlined),
              title: Text(game.title),
              subtitle: Text(
                  '${_consoles[game.entry.platform] ?? game.entry.platform} · ${_bytes(game.entry.bytes)}'),
              trailing: IconButton(
                  key: ValueKey('cache-pin-${game.entry.id}'),
                  tooltip: game.entry.pinned ? 'Unpin' : 'Pin',
                  icon: Icon(game.entry.pinned
                      ? Icons.push_pin
                      : Icons.push_pin_outlined),
                  onPressed: runtime.busy
                      ? null
                      : () => runtime.setPinned(
                          game.entry.id, !game.entry.pinned))),
        if (games.isEmpty)
          const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No managed ROMs installed.')),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(runtime.busy
          ? 'Checking cleanup…'
          : runtime.issue == null
              ? 'No cleanup errors'
              : _reason(runtime.issue!)),
      if (plan.blocked.any((item) => item.reason == 'clock_changed'))
        TextButton.icon(
            onPressed: runtime.busy ? null : runtime.acknowledgeClock,
            icon: const Icon(Icons.schedule),
            label: const Text('Clock checked')),
      for (final candidate in plan.victims)
        ListTile(
            leading: const Icon(Icons.cloud_done_outlined),
            title: Text(games
                .firstWhere((g) => g.entry.id == candidate.entry.id)
                .title),
            subtitle: Text(candidate.reasons.map(_reason).join(' · '))),
      for (final blocked in plan.blocked)
        ListTile(
            leading: const Icon(Icons.lock_outline),
            title: Text(
                games.firstWhere((g) => g.entry.id == blocked.entry.id).title),
            subtitle: Text(_reason(blocked.reason))),
      if (plan.unmetPools.isNotEmpty)
        const Text(
            'The requested limit cannot be met without removing protected or unavailable games.'),
      const SizedBox(height: 12),
      Wrap(spacing: 12, children: [
        OutlinedButton.icon(
            key: const ValueKey('cache-check'),
            onPressed: runtime.busy ? null : runtime.reconcile,
            icon: const Icon(Icons.refresh),
            label: const Text('Check now')),
        OutlinedButton.icon(
            key: const ValueKey('cache-stop'),
            onPressed: runtime.busy ? runtime.cancelAndJoin : null,
            icon: const Icon(Icons.stop),
            label: const Text('Stop')),
        OutlinedButton.icon(
            onPressed: () => Share.share(jsonEncode(draft.toJson()),
                subject: 'ROM cache settings'),
            icon: const Icon(Icons.ios_share),
            label: const Text('Export')),
      ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final runtime = _runtime, draft = _draft;
    final data = runtime?.latest;
    final plan = draft?.copyWith(enabled: true).plan(
        data?.games.map((g) => g.entry) ?? [],
        now: data?.time ?? DateTime.now().toUtc(),
        clockTrusted: data?.clockTrusted ?? false);
    return buildWithActions(
        Scaffold(
            backgroundColor: AppTheme.backgroundColor,
            appBar: AppBar(title: const Text('ROM cache')),
            body: runtime == null ||
                    draft == null ||
                    data == null ||
                    plan == null
                ? Center(
                    child: _problem == null
                        ? const CircularProgressIndicator()
                        : Text(_problem!))
                : LayoutBuilder(
                    builder: (context, box) => Row(children: [
                          NavigationRail(
                              key: const ValueKey('cache-sections'),
                              extended: box.maxWidth >= 680,
                              selectedIndex: _section.index,
                              onDestinationSelected: (index) => setState(
                                  () => _section = _CacheSection.values[index]),
                              destinations: const [
                                NavigationRailDestination(
                                    icon: Icon(Icons.tune),
                                    label: Text('Policy')),
                                NavigationRailDestination(
                                    icon: Icon(Icons.videogame_asset_outlined),
                                    label: Text('Consoles')),
                                NavigationRailDestination(
                                    icon: Icon(Icons.push_pin_outlined),
                                    label: Text('Games')),
                                NavigationRailDestination(
                                    icon: Icon(Icons.info_outline),
                                    label: Text('Status')),
                              ]),
                          const VerticalDivider(width: 1),
                          Expanded(
                              child: Column(children: [
                            Padding(
                                padding: const EdgeInsets.all(16),
                                child:
                                    Wrap(spacing: 24, runSpacing: 8, children: [
                                  Text(
                                      '${plan.eligibleGames} unpinned · ${_bytes(plan.eligibleBytes)}'),
                                  Text(
                                      '${plan.protectedGames} protected · ${_bytes(plan.protectedBytes)}'),
                                  Text(
                                      '${plan.victims.length} due after verification'),
                                ])),
                            if (_problem != null)
                              Text(_problem!,
                                  style:
                                      const TextStyle(color: Colors.redAccent)),
                            Expanded(
                                child: SingleChildScrollView(
                                    key: ValueKey(
                                        'cache-section-${_section.name}'),
                                    padding: EdgeInsets.all(
                                        box.maxWidth >= 680 ? 24 : 12),
                                    child: _body(plan))),
                            Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      if (!draft.enabled)
                                        const Expanded(
                                            child: Text(
                                                'Keep until manually removed')),
                                      FilledButton.icon(
                                          key: const ValueKey('cache-apply'),
                                          style: AppTheme.primaryButtonStyle,
                                          onPressed: _dirty && !runtime.busy
                                              ? _apply
                                              : null,
                                          icon: const Icon(Icons.check),
                                          label: const Text('Apply')),
                                    ])),
                          ])),
                        ]))),
        localFocusScope: true);
  }
}
