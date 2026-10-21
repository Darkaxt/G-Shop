// Isolated, app-owned renderer inspection; never boots library, saves or OAuth.
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:g_shop/core/theme/app_theme.dart';
import 'package:g_shop/features/preview/resource_gallery.dart';
import 'package:g_shop/models/system_model.dart';
import 'package:g_shop/models/socket_media_model.dart';
import 'package:g_shop/services/socket_media_import.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final info = await PackageInfo.fromPlatform();
  if (!kDebugMode ||
      !Platform.isAndroid ||
      info.packageName != 'com.darkaxt.rshop.sharedproof') {
    throw StateError('Requires isolated model inspection debug package');
  }
  // Prepare only this disposable package's oracle externally, before startup.
  // This app never requests root or reads another app's data itself.
  final support = await getApplicationSupportDirectory();
  final target = Directory('${support.path}/inspection-oracle');
  if (!await target.exists()) {
    throw StateError(
        'Prepare the app-private inspection-oracle before startup');
  }
  final seal =
      jsonDecode(await File('${target.path}/manifest.json').readAsString())
          as Map;
  final recipe = jsonDecode(
      await rootBundle.loadString('assets/socket_import_recipe.json')) as Map;
  final expected = <String>{
    'environment.json',
    'environment.astc',
    for (final model in recipe['models'] as List) ...[
      '${model['name']}.json',
      model['meshFile'] as String
    ],
    for (final texture in recipe['textures'] as List) texture['file'] as String
  };
  final files = (seal['files'] as Map).cast<String, String>();
  if (seal['schema'] != 1 ||
      seal['apkSha256'] != SocketMediaModel.apkSha256 ||
      !setEquals(files.keys.toSet(), expected)) {
    throw const FormatException('Invalid inspection oracle manifest');
  }
  for (final entry in files.entries) {
    SocketMediaDirectoryBundle.checkName(entry.key);
    final hash =
        await sha256.bind(File('${target.path}/${entry.key}').openRead()).first;
    if (hash.toString() != entry.value)
      throw const FormatException('Inspection oracle changed');
  }
  // A directory bundle still enforces each source JSON/mesh checksum at load.
  SocketMediaModel.importedBundle = SocketMediaDirectoryBundle(target);
  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.landscapeLeft]);
  final page = File('${support.path}/inspection-page.png');
  final data = await rootBundle.load('assets/icon.png');
  await page.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  runApp(MaterialApp(
      theme: AppTheme.darkTheme,
      home: Inspection(manual: page.uri.toString())));
}

class Inspection extends StatefulWidget {
  final String manual;
  const Inspection({super.key, required this.manual});
  @override
  State<Inspection> createState() => InspectionState();
}

class InspectionState extends State<Inspection> {
  final gallery = GlobalKey<ResourceGalleryState>();
  final next = GlobalKey();
  int index = 0;
  bool alternate = false;
  @override
  void initState() {
    super.initState();
    developer.registerExtension('ext.rshop.packaging', (_, args) async {
      try {
        final command = args['command'] ?? 'status';
        if (command == 'next') {
          (next.currentWidget as IconButton).onPressed!();
          await WidgetsBinding.instance.endOfFrame;
        } else if (command == 'view') {
          final mode = ResourceView.values.byName(args['view']!);
          // Exercise the actual visible ChoiceChip callback, not backend mutation.
          Element? found;
          void visit(Element node) {
            if (node.widget is ChoiceChip &&
                node.widget.key == ValueKey('resource-mode-${mode.name}'))
              found = node;
            node.visitChildren(visit);
          }

          context.visitChildElements(visit);
          (found!.widget as ChoiceChip).onSelected!(true);
          await WidgetsBinding.instance.endOfFrame;
        } else if (command == 'button') {
          IconButton? found;
          void visit(Element node) {
            if (node.widget is IconButton &&
                (node.widget as IconButton).tooltip == args['tooltip']) {
              found = node.widget as IconButton;
            }
            node.visitChildren(visit);
          }

          context.visitChildElements(visit);
          if (found?.onPressed == null)
            throw StateError('Visible control unavailable');
          found!.onPressed!();
          await WidgetsBinding.instance.endOfFrame;
        } else if (command != 'status' && command != 'ready') {
          throw StateError('Unknown inspection action');
        }
        final renderer = gallery.currentState?.rendererKey.currentState;
        if (renderer != null) await renderer.currentFrameReady;
        return developer.ServiceExtensionResponse.result(jsonEncode({
          'system': SystemModel.supportedSystems[index].id,
          'alternate': alternate,
          'gallery': gallery.currentState?.snapshot,
          'source': 'isolated-renderer-inspection',
          'sourceRevision': 's25-explorer-r4',
        }));
      } catch (error) {
        return developer.ServiceExtensionResponse.error(
            developer.ServiceExtensionResponse.extensionError,
            error.toString());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final system = SystemModel.supportedSystems[index];
    return Scaffold(
        appBar: AppBar(title: Text('Model check: ${system.id}'), actions: [
          IconButton(
              tooltip: 'Region',
              onPressed: () => setState(() => alternate = !alternate),
              icon: const Icon(Icons.public)),
          IconButton(
              key: next,
              tooltip: 'Next console',
              onPressed: () => setState(() =>
                  index = (index + 1) % SystemModel.supportedSystems.length),
              icon: const Icon(Icons.skip_next))
        ]),
        body: ResourceGallery(
            key: gallery,
            identity: 'inspect:${system.id}:$alternate',
            title: '${system.name} inspection',
            systemId: system.id,
            region: alternate ? 'eu' : 'us',
            dualMode: alternate ? 'No' : 'Yes',
            resources: {
              'manual-page': [widget.manual]
            },
            importedModels: true));
  }
}
