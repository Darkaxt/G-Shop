// Isolated renderer proof. Never bootstraps the owner's library or credentials.
// VM service extensions are authenticated by the debug VM's session URL and
// reachable only through an explicitly selected ADB forward during this check.
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:retro_eshop/widgets/physical_media_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final info = await PackageInfo.fromPlatform();
  if (!kDebugMode ||
      !Platform.isAndroid ||
      info.packageName != 'com.darkaxt.rshop.sharedproof') {
    throw StateError(
        'Renderer proof requires its isolated Android debug package');
  }
  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.landscapeLeft]);
  runApp(const MaterialApp(
      debugShowCheckedModeBanner: false, home: _MediaProof()));
}

class _MediaProof extends StatefulWidget {
  const _MediaProof();
  @override
  State<_MediaProof> createState() => _MediaProofState();
}

class _MediaProofState extends State<_MediaProof> {
  final _media = GlobalKey<PhysicalMediaViewState>();
  final _next = GlobalKey(), _previous = GlobalKey(), _insert = GlobalKey();
  final _artwork = GlobalKey();
  int _index = 0, _revision = 0;
  bool _resolved = false, _busy = false;
  Future<void> _action = Future.value();

  PhysicalMediaFormat get _format => PhysicalMediaFormat.values[_index];

  @override
  void initState() {
    super.initState();
    developer.registerExtension('ext.rshop.media', (_, args) async {
      try {
        final command = args['command'] ?? 'status';
        final before = _revision;
        if (command == 'ready') {
          await _media.currentState!.renderReady;
        } else if (command != 'status') {
          final key = switch (command) {
            'next' => _next,
            'previous' => _previous,
            'insert' => _insert,
            'artwork' => _artwork,
            _ => throw ArgumentError('Unknown proof action'),
          };
          final control = key.currentWidget as FilledButton;
          if (control.onPressed == null) throw StateError('Control disabled');
          control.onPressed!(); // The same callback as an actual UI press.
          await _action;
          await WidgetsBinding.instance.endOfFrame;
        }
        return developer.ServiceExtensionResponse.result(jsonEncode({
          'action': command,
          'beforeRevision': before,
          'afterRevision': _revision,
          ..._snapshot(),
        }));
      } catch (error) {
        return developer.ServiceExtensionResponse.error(
            developer.ServiceExtensionResponse.extensionError, '$error');
      }
    });
  }

  Map<String, Object?> _snapshot() {
    Map<String, Object?> node(String id, GlobalKey key, String role) {
      final box = key.currentContext?.findRenderObject() as RenderBox?;
      final origin = box?.localToGlobal(Offset.zero);
      final button = key.currentWidget;
      return {
        'id': id,
        'role': role,
        'parent': 'proof',
        'boundsLogicalPixels': box?.hasSize == true
            ? [origin!.dx, origin.dy, box!.size.width, box.size.height]
            : null,
        'enabled': button is FilledButton ? button.onPressed != null : true,
      };
    }

    return {
      'package': 'com.darkaxt.rshop.sharedproof',
      'debug': kDebugMode,
      'format': _format.assetName,
      'resolvedFixtureLabel': _resolved,
      'renderer': _media.currentState?.renderSnapshot,
      'viewportLogicalPixels': [
        MediaQuery.sizeOf(context).width,
        MediaQuery.sizeOf(context).height
      ],
      'nodes': [
        node('media', _media, 'physical-media'),
        node('previous', _previous, 'button'),
        node('next', _next, 'button'),
        node('insert', _insert, 'button'),
        node('artwork', _artwork, 'button')
      ],
      'coverageLimit':
          'Isolated real renderer; not owner-library data or launch proof',
    };
  }

  void _move(int delta) {
    _media.currentState?.resetInsertion();
    setState(() {
      _index = (_index + delta) % PhysicalMediaFormat.values.length;
      _revision++;
    });
    _action = Future.value();
  }

  void _play() {
    setState(() => _busy = true);
    _action = () async {
      final completed = await _media.currentState!.playInsertion();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _revision++;
      });
      if (!completed) throw StateError('Insertion cancelled');
    }();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: const Color(0xff39070d),
      body: SafeArea(
          child: Column(children: [
        Padding(
            padding: const EdgeInsets.all(12),
            child: Text('Socket media: ${_format.description}',
                style: const TextStyle(color: Colors.white, fontSize: 24))),
        Expanded(
            child: PhysicalMediaView(
                key: _media,
                identity: 'fixture-${_format.assetName}',
                title: 'Renderer sample',
                format: _format,
                label: _resolved
                    ? const ColoredBox(
                        color: Color(0xfff7d96b),
                        child: Center(
                            child: Text('TOP ↑\nLEFT ←  LABEL  → RIGHT',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.black, fontSize: 24))))
                    : const HandwrittenMediaSticker(
                        identity: 'fixture', title: 'Renderer sample'))),
        Padding(
            padding: const EdgeInsets.all(12),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              FilledButton(
                  key: _previous,
                  onPressed: _busy ? null : () => _move(-1),
                  child: const Icon(Icons.arrow_back)),
              const SizedBox(width: 12),
              FilledButton(
                  key: _next,
                  onPressed: _busy ? null : () => _move(1),
                  child: const Icon(Icons.arrow_forward)),
              const SizedBox(width: 12),
              FilledButton(
                  key: _insert,
                  onPressed: _busy ? null : _play,
                  child: const Icon(Icons.play_arrow)),
              const SizedBox(width: 12),
              FilledButton(
                  key: _artwork,
                  onPressed: _busy
                      ? null
                      : () {
                          _media.currentState?.resetInsertion();
                          setState(() {
                            _resolved = !_resolved;
                            _revision++;
                          });
                          _action = Future.value();
                        },
                  child: const Icon(Icons.image)),
            ])),
      ])));
}
