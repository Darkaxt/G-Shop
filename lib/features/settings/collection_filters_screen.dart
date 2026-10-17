import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/input/input.dart';
import '../../core/theme/app_theme.dart';
import '../../models/commercial_release_preference.dart';
import '../../providers/collection_preferences_provider.dart';

class CollectionFiltersScreen extends ConsumerStatefulWidget {
  const CollectionFiltersScreen({super.key});
  @override
  ConsumerState<CollectionFiltersScreen> createState() =>
      _CollectionFiltersState();
}

class _CollectionFiltersState extends ConsumerState<CollectionFiltersScreen>
    with ConsoleScreenMixin {
  int _section = 0;
  String? _error;
  final _orderFocus = <String, FocusNode>{};
  FocusNode _focus(String key) =>
      _orderFocus.putIfAbsent(key, () => FocusNode(debugLabel: key));
  @override
  void dispose() {
    for (final node in _orderFocus.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  String get routeId => 'collection-filters';
  @override
  Map<Type, Action<Intent>> get screenActions => {
        TabLeftIntent:
            CallbackAction<TabLeftIntent>(onInvoke: (_) => _switchSection()),
        TabRightIntent:
            CallbackAction<TabRightIntent>(onInvoke: (_) => _switchSection()),
        BackIntent: CallbackAction<BackIntent>(onInvoke: (_) {
          Navigator.maybePop(context);
          return null;
        }),
        ConfirmIntent: CallbackAction<ConfirmIntent>(onInvoke: (_) {
          final target = FocusManager.instance.primaryFocus?.context;
          if (target != null)
            Actions.maybeInvoke(target, const ActivateIntent());
          return null;
        }),
        NavigateIntent: CallbackAction<NavigateIntent>(onInvoke: (intent) {
          final focus = FocusManager.instance.primaryFocus;
          if (focus == null || focus == screenFocusNode) {
            screenFocusNode.nextFocus();
          } else {
            focus.focusInDirection(switch (intent.direction) {
              GridDirection.up => TraversalDirection.up,
              GridDirection.down => TraversalDirection.down,
              GridDirection.left => TraversalDirection.left,
              GridDirection.right => TraversalDirection.right,
            });
          }
          return null;
        }),
      };

  Object? _switchSection() {
    setState(() => _section = 1 - _section);
    return null;
  }

  Future<void> _save(CommercialReleasePreference next) async {
    try {
      await ref.read(collectionPreferencesProvider.notifier).change(next);
      if (mounted) setState(() => _error = null);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save this setting.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final preference = ref.watch(collectionPreferencesProvider);
    return buildWithActions(Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(title: const Text('Collection filters')),
      body: LayoutBuilder(
          builder: (context, bounds) => Row(children: [
                NavigationRail(
                  selectedIndex: _section,
                  extended: bounds.maxWidth >= 680,
                  onDestinationSelected: (value) =>
                      setState(() => _section = value),
                  destinations: const [
                    NavigationRailDestination(
                        icon: Icon(Icons.layers_outlined),
                        label: Text('Versions')),
                    NavigationRailDestination(
                        icon: Icon(Icons.public), label: Text('Region order')),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(
                    child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_section == 0) ...[
                          SwitchListTile(
                            key: const ValueKey('show-all-versions'),
                            secondary: const Icon(Icons.layers_outlined),
                            title: const Text('Show all versions'),
                            subtitle: const Text(
                                'Keep regional alternatives in the game’s version picker.'),
                            value: preference.showAllVersions,
                            onChanged: (value) =>
                                _save(preference.showingAll(value)),
                          ),
                          const SizedBox(height: 24),
                          Text(
                              preference.showAllVersions
                                  ? 'All available regions'
                                  : preference.regions.join(' → '),
                              style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 12),
                          const Text(
                              'Commercial games only. Hacks and patches stay unchanged.\n'
                              'Each game still takes one Top position. No files are removed.'),
                        ] else ...[
                          Text('Preferred regions',
                              style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 8),
                          const Text(
                              'First available region wins. Other regions remain available when none match.'),
                          const SizedBox(height: 16),
                          for (var index = 0;
                              index < preference.regions.length;
                              index++)
                            ListTile(
                              key: ValueKey(
                                  'region-${preference.regions[index]}'),
                              leading:
                                  CircleAvatar(child: Text('${index + 1}')),
                              title: Text(preference.regions[index]),
                              trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                        focusNode: _focus(
                                            'up-${preference.regions[index]}'),
                                        key: ValueKey(
                                            'region-up-${preference.regions[index]}'),
                                        tooltip: 'Move up',
                                        icon: const Icon(Icons.arrow_upward),
                                        onPressed: index == 0
                                            ? null
                                            : () => _save(
                                                preference.move(index, -1))),
                                    IconButton(
                                        focusNode: _focus(
                                            'down-${preference.regions[index]}'),
                                        key: ValueKey(
                                            'region-down-${preference.regions[index]}'),
                                        tooltip: 'Move down',
                                        icon: const Icon(Icons.arrow_downward),
                                        onPressed: index ==
                                                preference.regions.length - 1
                                            ? null
                                            : () => _save(
                                                preference.move(index, 1))),
                                  ]),
                            ),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                              key: const ValueKey('reset-region-order'),
                              onPressed: () => _save(
                                  CommercialReleasePreference(
                                      showAllVersions:
                                          preference.showAllVersions)),
                              icon: const Icon(Icons.restart_alt),
                              label: const Text('Reset order')),
                        ],
                        if (_error != null) Text(_error!),
                      ]),
                )),
              ])),
    ));
  }
}
