import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/console_model.dart';
import '../../models/system_model.dart';
import '../../providers/app_providers.dart';
import '../../providers/preview_providers.dart';
import '../../services/secondary_preview.dart';
import 'dual_screen_preview_host.dart';

/// Only the visible console-selection route owns this presentation. It never
/// requests input focus or changes the ROM/companion presentation's ownership.
class ConsolePreviewHost extends ConsumerStatefulWidget {
  final SystemModel? system;
  final Widget child;
  const ConsolePreviewHost(
      {super.key, required this.system, required this.child});
  @override
  ConsumerState<ConsolePreviewHost> createState() => _ConsolePreviewHostState();
}

class _ConsolePreviewHostState extends ConsumerState<ConsolePreviewHost>
    with RouteAware, WidgetsBindingObserver {
  ModalRoute<void>? _route;
  SecondaryPreview? _bridge;
  String? _request;
  int _generation = 0;
  bool _visible = true, _resumed = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != _route) {
      previewRouteObserver.unsubscribe(this);
      _route = route;
      if (route != null) previewRouteObserver.subscribe(this, route);
    }
  }

  void _hide() {
    _generation++;
    _request = null;
    unawaited(_bridge?.hide(this));
  }

  @override
  void didPushNext() {
    _visible = false;
    _hide();
  }

  @override
  void didPopNext() {
    _visible = true;
    _request = null;
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    if (!_resumed) _hide();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    _bridge = ref.watch(secondaryPreviewProvider);
    final prefs = ref.watch(previewSettingsProvider);
    final reduced = ref.watch(mediaPresentationProvider).reducedMotion;
    final system = widget.system;
    final enabled = _visible &&
        _resumed &&
        system != null &&
        prefs.enabled &&
        prefs.modelVisible &&
        _bridge!.available;
    final signature =
        jsonEncode([enabled, system?.id, prefs.toJson(), reduced]);
    if (_request != signature) {
      _request = signature;
      final generation = ++_generation;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || generation != _generation) return;
        if (!enabled) {
          await _bridge?.hide(this);
          return;
        }
        try {
          final model = await ConsoleModel.find(system.id);
          if (!mounted || generation != _generation || !_visible || !_resumed)
            return;
          if (model == null) {
            await _bridge?.hide(this);
            return;
          }
          await _bridge?.present(
              this,
              {
                'mode': 'console',
                'identity': 'console:${system.id}:${model.generation}',
                'actionIdentity': 'console:${system.id}',
                'system': system.id,
                'title': system.name,
                'consoleGeneration': model.generation,
                'reducedMotion': reduced,
                'settings': prefs.toJson(),
              },
              (_, __) async {});
        } catch (error) {
          if (!mounted || generation != _generation) return;
          debugPrint('GShopConsolePreview import unavailable: $error');
          await _bridge?.hide(this);
        }
      });
    }
    return widget.child;
  }

  @override
  void dispose() {
    _hide();
    previewRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
