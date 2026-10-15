import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_actions.dart';
import 'app_intents.dart';

/// App-owned Material dialogs share the same A/B and directional controls as
/// their page. Navigator popup routes do not inherit that page's Actions.
Future<T?> showConsoleDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) =>
    showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (context) => ScreenActionsWrapper(
        materialControls: true,
        child: FocusScope(autofocus: true, child: builder(context)),
      ),
    );

class GlobalInputWrapper extends ConsumerStatefulWidget {
  final Widget child;

  const GlobalInputWrapper({
    super.key,
    required this.child,
  });

  @override
  ConsumerState<GlobalInputWrapper> createState() => _GlobalInputWrapperState();
}

class _GlobalInputWrapperState extends ConsumerState<GlobalInputWrapper> {
  late final FocusNode _rootFocusNode;

  @override
  void initState() {
    super.initState();
    _rootFocusNode =
        FocusNode(debugLabel: 'GlobalInputRoot', skipTraversal: true);
  }

  @override
  void dispose() {
    _rootFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: AppShortcuts.defaultShortcuts,
      child: Actions(
        actions: _buildActions(context),
        child: Focus(
          focusNode: _rootFocusNode,
          autofocus: true,
          child: widget.child,
        ),
      ),
    );
  }

  Map<Type, Action<Intent>> _buildActions(BuildContext context) {
    return {
      BackIntent: BackAction(context, ref),
      ConfirmIntent: ConfirmAction(ref),
      SearchIntent: SearchAction(ref),
      ToggleOverlayIntent: ToggleOverlayAction(ref),
      NavigateIntent: NavigateAction(ref),
      AdjustColumnsIntent: AdjustColumnsAction(ref),
      MenuIntent: MenuAction(ref),
    };
  }
}

class ScreenActionsWrapper extends ConsumerWidget {
  final Widget child;
  final Map<Type, Action<Intent>> screenActions;
  final Map<ShortcutActivator, Intent>? additionalShortcuts;
  final bool materialControls;

  const ScreenActionsWrapper({
    super.key,
    required this.child,
    this.screenActions = const {},
    this.additionalShortcuts,
    this.materialControls = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final combinedShortcuts = <ShortcutActivator, Intent>{
      ...AppShortcuts.defaultShortcuts,
      // Tabbed pages own the shoulder buttons; PageUp/PageDown retain grid zoom.
      if (screenActions.containsKey(TabLeftIntent))
        const SingleActivator(LogicalKeyboardKey.gameButtonLeft1,
            includeRepeats: false): const TabLeftIntent(),
      if (screenActions.containsKey(TabRightIntent))
        const SingleActivator(LogicalKeyboardKey.gameButtonRight1,
            includeRepeats: false): const TabRightIntent(),
      if (additionalShortcuts != null) ...additionalShortcuts!,
    };

    return Shortcuts(
      shortcuts: combinedShortcuts,
      child: Actions(
        actions: {
          if (materialControls) ...{
            BackIntent: CallbackAction<BackIntent>(onInvoke: (_) {
              Navigator.maybePop(context);
              return null;
            }),
            ConfirmIntent: CallbackAction<ConfirmIntent>(onInvoke: (_) {
              final target = primaryFocus?.context;
              if (target != null) {
                Actions.maybeInvoke(target, const ActivateIntent());
              }
              return null;
            }),
            NavigateIntent: CallbackAction<NavigateIntent>(onInvoke: (intent) {
              final focus = primaryFocus;
              if (focus?.skipTraversal == true) {
                focus?.nextFocus();
                return null;
              }
              focus?.focusInDirection(switch (intent.direction) {
                GridDirection.up => TraversalDirection.up,
                GridDirection.down => TraversalDirection.down,
                GridDirection.left => TraversalDirection.left,
                GridDirection.right => TraversalDirection.right,
              });
              return null;
            }),
          },
          ...screenActions,
        },
        child: child,
      ),
    );
  }
}
