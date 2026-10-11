import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/input/overlay_scope.dart';
import '../../../core/input/input_providers.dart';
import '../../../services/storage_service.dart';

/// An explicit per-edition selection. Saving must be acknowledged before closing.
class CompanionPickerDialog extends StatefulWidget {
  final StorageService storage;
  final String editionId;
  final Future<List<Map<String, String>>> applications;

  const CompanionPickerDialog({
    super.key,
    required this.storage,
    required this.editionId,
    required this.applications,
  });

  @override
  State<CompanionPickerDialog> createState() => _CompanionPickerDialogState();
}

class _CompanionPickerDialogState extends State<CompanionPickerDialog> {
  final _focus = FocusNode(debugLabel: 'CompanionPicker');
  final _scroll = ScrollController();
  List<Map<String, String>> _apps = const [];
  int _index = 0;
  bool _loading = true;
  bool _loadFailed = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.applications.then((apps) {
      if (mounted) {
        setState(() {
          _apps = apps;
          _loading = false;
        });
      }
    }, onError: (Object _, StackTrace __) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadFailed = true;
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _close() {
    if (!_saving) Navigator.pop(context);
  }

  Future<void> _choose(int index) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.storage.setCompanion(
          widget.editionId, index == 0 ? null : _apps[index - 1]['component']);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save your choice. Please try again.';
        });
      }
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.gameButtonB ||
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.backspace) {
      _close();
      return KeyEventResult.handled;
    }
    if (_saving) return KeyEventResult.handled;
    if (key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.space) {
      _choose(_index);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      setState(() => _index =
          (_index + (key == LogicalKeyboardKey.arrowDown ? 1 : -1))
              .clamp(0, _apps.length));
      if (_scroll.hasClients) {
        final position = _scroll.position;
        final start = _index * 72.0;
        final end = start + 72;
        if (start < position.pixels) {
          _scroll.jumpTo(start.clamp(0, position.maxScrollExtent));
        } else if (end > position.pixels + position.viewportDimension) {
          _scroll.jumpTo((end - position.viewportDimension)
              .clamp(0, position.maxScrollExtent));
        }
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.storage.getCompanion(widget.editionId);
    final unavailable = current != null &&
        !_loading &&
        !_loadFailed &&
        !_apps.any((app) => app['component'] == current);
    return PopScope(
      canPop: !_saving,
      child: OverlayFocusScope(
        priority: OverlayPriority.dialog,
        isVisible: true,
        onClose: _close,
        child: Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _handleKey,
          child: AlertDialog(
            backgroundColor: const Color(0xFF1A1A1A),
            title: const Text('Companion on bottom screen',
                style: TextStyle(color: Colors.white, fontSize: 20)),
            content: SizedBox(
              width: 480,
              height: (MediaQuery.sizeOf(context).height * .5).clamp(160, 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                      'Choose an app to open on the bottom screen when you play this version of the game on the top screen.',
                      style: TextStyle(color: Colors.white70)),
                  if (unavailable)
                    const Text(
                        'The selected app can no longer be opened. Choose another app or None.',
                        style: TextStyle(color: Colors.amber)),
                  if (_loadFailed)
                    const Text(
                        'Could not load your installed apps. You can still choose None to turn this off.',
                        style: TextStyle(color: Colors.amber)),
                  if (_loading || _saving) const LinearProgressIndicator(),
                  if (_error != null)
                    Text(_error!, style: const TextStyle(color: Colors.amber)),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.builder(
                      controller: _scroll,
                      itemExtent: 72,
                      itemCount: _apps.length + 1,
                      itemBuilder: (context, index) {
                        final app = index == 0 ? null : _apps[index - 1];
                        final selected = current == app?['component'];
                        return Semantics(
                          button: true,
                          selected: selected,
                          enabled: !_saving,
                          child: InkWell(
                            canRequestFocus: false,
                            onTap: _saving ? null : () => _choose(index),
                            onHover: (hover) {
                              if (hover && !_saving) {
                                setState(() => _index = index);
                              }
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                    color: _index == index
                                        ? Colors.cyanAccent
                                        : Colors.transparent),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: ListTile(
                                leading: Icon(
                                    index == 0
                                        ? Icons.apps_outlined
                                        : Icons.smartphone,
                                    color: Colors.white70),
                                title: Text(app?['label'] ?? 'None · game only',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        const TextStyle(color: Colors.white)),
                                subtitle: app == null
                                    ? null
                                    : Text(app['component']!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 12)),
                                trailing: selected
                                    ? const Icon(Icons.check,
                                        color: Colors.cyanAccent)
                                    : null,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: _saving ? null : _close,
                  child: const Text('Cancel · B'))
            ],
          ),
        ),
      ),
    );
  }
}
