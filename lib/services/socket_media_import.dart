import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../models/socket_media_model.dart';
import 'socket_mesh_import.dart';

/// The selected generation is immutable. Only a fully validated import replaces
/// the small active pointer; failed/cancelled jobs cannot replace a usable copy.
class SocketMediaImport extends ChangeNotifier {
  static final instance = SocketMediaImport();
  final Directory? directory;
  final MethodChannel channel;
  SocketMediaImport(
      {this.directory,
      this.channel = const MethodChannel('com.retro.rshop/socket_import')});
  Directory? _root, _active;
  Future<void>? _initializing;
  String? _session;
  bool importing = false, committing = false, _cancelled = false;
  String phase = '', message = '';
  double progress = 0;
  bool get available => _active != null;
  String? get generation => _active?.path.split(Platform.pathSeparator).last;

  Future<void> initialize() => _initializing ??= _initialize();
  Future<void> _initialize() async {
    _root = directory ??
        Directory(
            '${(await getApplicationSupportDirectory()).path}/socket-media');
    try {
      // Claimed once per native process, before the first UI can consume media.
      // Hot restart or a second engine cannot clean a live engine's import.
      final cleanup =
          await channel.invokeMethod<bool>('startupCleanup') == true;
      if (!await _root!.exists()) return;
      final entries = _root!.listSync(followLinks: false);
      final pointer = File('${_root!.path}/active.json');
      final saved = pointer.existsSync() ? pointer.readAsStringSync() : null;
      if (cleanup) {
        for (final entry in entries) {
          final name = entry.path.split(Platform.pathSeparator).last;
          if (entry is Directory &&
              RegExp(r'^\.incoming-[a-f0-9]{32}$').hasMatch(name)) {
            await entry.delete(recursive: true);
          }
        }
      }
      if (saved == null) return;
      final name = (jsonDecode(saved) as Map)['generation'] as String;
      if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(name)) {
        throw const FormatException('Invalid media generation');
      }
      final selected = Directory('${_root!.path}/$name');
      await _validate(selected);
      _activate(selected);
      // Previous generations were retained only for live views during the
      // preceding process. Startup has no such consumers; the active pointer
      // and its fully validated generation are never cleanup targets.
      try {
        for (final entry in cleanup ? entries : <FileSystemEntity>[]) {
          final oldName = entry.path.split(Platform.pathSeparator).last;
          if (entry is Directory &&
              oldName != name &&
              RegExp(r'^[a-f0-9]{32}$').hasMatch(oldName)) {
            final manifest = File('${entry.path}/manifest.json');
            if (await manifest.exists()) {
              final seal = jsonDecode(await manifest.readAsString()) as Map;
              if (seal['schema'] == 1 &&
                  seal['apkSha256'] == SocketMediaModel.apkSha256) {
                await entry.delete(recursive: true);
              }
            }
          }
        }
      } catch (_) {
        message = 'Older preview resources could not be removed.';
      }
    } catch (_) {
      message =
          'Imported media is unavailable. Import the APK again to use 3D.';
    }
  }

  void _activate(Directory directory) {
    _active = directory;
    SocketMediaModel.importedBundle = SocketMediaDirectoryBundle(directory);
    notifyListeners();
  }

  Future<void> _validate(Directory directory) async {
    final recipe = jsonDecode(
        await rootBundle.loadString('assets/socket_import_recipe.json')) as Map;
    final seal =
        jsonDecode(await File('${directory.path}/manifest.json').readAsString())
            as Map;
    if (seal['schema'] != 1 ||
        seal['apkSha256'] != SocketMediaModel.apkSha256) {
      throw const FormatException('Invalid imported media');
    }
    final expected = <String>{'environment.json', 'environment.astc'};
    for (final model in recipe['models'] as List) {
      expected.add('${model['name']}.json');
      expected.add(model['meshFile'] as String);
    }
    expected
        .addAll((recipe['textures'] as List).map((t) => t['file'] as String));
    final files = (seal['files'] as Map).cast<String, String>();
    if (!setEquals(files.keys.toSet(), expected)) {
      throw const FormatException('Incomplete imported media');
    }
    for (final file in files.entries) {
      SocketMediaDirectoryBundle.checkName(file.key);
      final hash = await sha256
          .bind(File('${directory.path}/${file.key}').openRead())
          .first;
      if (hash.toString() != file.value) {
        throw const FormatException('Imported media checksum mismatch');
      }
    }
    final bundle = SocketMediaDirectoryBundle(directory);
    for (final format in PhysicalMediaFormat.values) {
      await SocketMediaModel.load(format, bundle: bundle);
    }
    await SocketMediaModel.loadEnvironment(bundle: bundle);
  }

  void cancel() {
    if (!importing || committing) return;
    _cancelled = true;
    final session = _session;
    if (session != null) {
      channel.invokeMethod<void>('cancel', {'session': session});
    }
  }

  void _checkCancellation() {
    if (_cancelled) throw PlatformException(code: 'cancelled');
  }

  Future<Uint8List> _resource(String member, {bool decompress = false}) async {
    _checkCancellation();
    final bytes = await channel.invokeMethod<Uint8List>('resource', {
      'session': _session,
      'member': member,
      'decompress': decompress,
    });
    _checkCancellation();
    if (bytes == null) throw const FormatException('Missing imported resource');
    return bytes;
  }

  Future<void> importApk(File original) async {
    if (importing) throw StateError('An import is already running');
    importing = true;
    _cancelled = false;
    progress = 0;
    phase = 'Checking APK';
    message = '';
    notifyListeners();
    try {
      await initialize();
    } catch (_) {
      importing = false;
      notifyListeners();
      rethrow;
    }
    final random = math.Random.secure();
    final id = List.generate(
            16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
    final stage = Directory('${_root!.path}/.incoming-$id');
    final nextPointer = File('${_root!.path}/active.$id.next');
    Directory? published;
    try {
      await stage.create(recursive: true);
      if (await original.length() != 153715341) {
        throw const FormatException('Choose the original Socket 0.7 APK');
      }
      final snapshot = File('${stage.path}/source.apk');
      final sink = snapshot.openWrite();
      try {
        await for (final bytes in original.openRead()) {
          _checkCancellation();
          sink.add(bytes);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      _checkCancellation();
      _session =
          await channel.invokeMethod<String>('open', {'path': snapshot.path});
      if (_session == null) {
        throw const FormatException('APK import could not start');
      }
      _checkCancellation();
      final recipe = jsonDecode(
              await rootBundle.loadString('assets/socket_import_recipe.json'))
          as Map;
      if (recipe['apkSha256'] != SocketMediaModel.apkSha256 ||
          recipe['schema'] != 1) {
        throw const FormatException('Unsupported resource recipe');
      }
      final files = <String, String>{};
      Future<void> write(String name, Uint8List bytes) async {
        _checkCancellation();
        SocketMediaDirectoryBundle.checkName(name);
        await File('${stage.path}/$name').writeAsBytes(bytes, flush: true);
        files[name] = sha256.convert(bytes).toString();
      }

      final models = (recipe['models'] as List).cast<Map<String, dynamic>>();
      final textures =
          (recipe['textures'] as List).cast<Map<String, dynamic>>();
      final total = models.length + textures.length + 1;
      var completed = 0;
      for (final description in models) {
        phase = 'Importing ${description['name']}';
        notifyListeners();
        final sourceScript =
            await _resource(description['animationMember'] as String);
        if (sha256.convert(sourceScript).toString() !=
            description['animationSourceSha256']) {
          throw const FormatException('Source animation checksum mismatch');
        }
        final resources = <String, ByteData>{};
        for (final surface in description['surfaces'] as List) {
          final member = surface['import']['member'] as String;
          if (!resources.containsKey(member)) {
            resources[member] =
                ByteData.sublistView(await _resource(member, decompress: true));
          }
        }
        final mesh = await compute(_convertMesh, (description, resources));
        if (sha256.convert(mesh).toString() != description['meshSha256']) {
          throw const FormatException('Converted source geometry differs');
        }
        await write(description['meshFile'] as String, mesh);
        final model =
            jsonDecode(jsonEncode(description)) as Map<String, dynamic>;
        model.remove('normalizationCenter');
        model.remove('animationMember');
        for (final surface in model['surfaces'] as List) {
          surface.remove('import');
        }
        await write('${model['name']}.json',
            Uint8List.fromList(utf8.encode(jsonEncode(model))));
        progress = ++completed / total;
        notifyListeners();
      }
      for (final texture in textures) {
        phase = 'Importing materials';
        notifyListeners();
        final Uint8List rgba;
        if (texture['format'] == 'source-procedural-rgba8') {
          final source = await _resource(texture['sourceMember'] as String);
          if (sha256.convert(source).toString() != texture['resourceSha256']) {
            throw const FormatException('Procedural source checksum mismatch');
          }
          rgba = await _procedural(texture);
        } else {
          final result = await channel.invokeMethod<Uint8List>('texture', {
            'session': _session,
            'member': texture['sourceMember'],
            'sha256': texture['sourceSha256'],
            'width': texture['width'],
            'height': texture['height'],
            'format': texture['format'],
          });
          if (result == null) {
            throw const FormatException('Missing source texture');
          }
          rgba = result;
        }
        if (sha256.convert(rgba).toString() != texture['pixelsSha256']) {
          throw const FormatException('Decoded source texture differs');
        }
        final png = await compute(encodeSocketTexture,
            (texture['width'] as int, texture['height'] as int, rgba));
        await write(texture['file'] as String, png);
        progress = ++completed / total;
        notifyListeners();
      }
      phase = 'Checking imported media';
      notifyListeners();
      final environment = recipe['environment'] as Map<String, dynamic>;
      final scene = await _resource(environment['sourceSceneMember'] as String);
      if (sha256.convert(scene).toString() !=
          environment['sourceSceneSha256']) {
        throw const FormatException('Source environment scene differs');
      }
      final sky = await _resource(environment['sourceMember'] as String);
      if (sha256.convert(sky).toString() != environment['sourceSha256'] ||
          sky.length < 52) {
        throw const FormatException('Source HDR environment differs');
      }
      final blocks = Uint8List.sublistView(sky, 52);
      if (sha256.convert(blocks).toString() != environment['pixelsSha256']) {
        throw const FormatException('Source HDR blocks differ');
      }
      await write('environment.astc', blocks);
      await write('environment.json',
          Uint8List.fromList(utf8.encode(jsonEncode(environment))));
      await channel.invokeMethod<void>('close', {'session': _session});
      _session = null;
      await snapshot.delete();
      await File('${stage.path}/manifest.json').writeAsString(
          jsonEncode({
            'schema': 1,
            'apkSha256': SocketMediaModel.apkSha256,
            'files': files,
          }),
          flush: true);
      await _validate(stage);
      _checkCancellation();
      published = await stage.rename('${_root!.path}/$id');
      await nextPointer.writeAsString(jsonEncode({'generation': id}),
          flush: true);
      _checkCancellation();
      committing = true;
      phase = 'Activating previews';
      notifyListeners();
      // Android/POSIX rename publishes the pointer atomically, replacing the old
      // pointer only after every member of the new immutable generation validates.
      await nextPointer.rename('${_root!.path}/active.json');
      _activate(published);
      progress = 1;
      message = 'Imported. You can now enable 3D media.';
    } catch (error) {
      message = _cancelled ||
              error is PlatformException && error.code == 'cancelled'
          ? 'Import cancelled. Your previous media is unchanged.'
          : 'Could not import this APK. Choose the original Socket 0.7 file.';
      if (published != null && published.path != _active?.path) {
        await published.delete(recursive: true);
      }
      rethrow;
    } finally {
      final session = _session;
      _session = null;
      try {
        if (session != null) {
          await channel.invokeMethod<void>('close', {'session': session});
        }
      } finally {
        try {
          if (await stage.exists()) await stage.delete(recursive: true);
          if (await nextPointer.exists()) await nextPointer.delete();
        } finally {
          importing = false;
          committing = false;
          phase = '';
          notifyListeners();
        }
      }
    }
  }

  Future<Uint8List> _procedural(Map<String, dynamic> texture) async {
    final tree = texture['sourceTree'] as Map;
    final props = tree['properties'] as Map;
    final width = texture['width'] as int, height = texture['height'] as int;
    Float32List? noise;
    if (tree['type'] == 'NoiseTexture2D') {
      final settings = props['noise']['properties'] as Map;
      final offset = (settings['offset']?['values'] as List?) ?? [0, 0, 0];
      noise = await channel.invokeMethod<Float32List>('noise', {
        'session': _session,
        'width': width,
        'height': height,
        'settings': [
          settings['seed'] ?? 0,
          settings['noise_type'] ?? 1,
          settings['frequency'] ?? .01,
          settings['fractal_type'] ?? 1,
          settings['fractal_octaves'] ?? 5,
          settings['fractal_lacunarity'] ?? 2,
          settings['fractal_gain'] ?? .5,
          settings['fractal_weighted_strength'] ?? 0,
          settings['fractal_ping_pong_strength'] ?? 2,
          settings['cellular_distance_function'] ?? 0,
          settings['cellular_return_type'] ?? 1,
          settings['cellular_jitter'] ?? 1,
          offset[0],
          offset[1]
        ],
      });
      if (noise == null) {
        throw const FormatException('Missing procedural noise');
      }
    }
    return compute(_proceduralPixels, (texture, noise));
  }
}

Uint8List _convertMesh((Map<String, dynamic>, Map<String, ByteData>) input) =>
    convertSocketMesh(input.$1, input.$2).buffer.asUint8List();
Uint8List encodeSocketTexture((int, int, Uint8List) input) =>
    img.encodePng(img.Image.fromBytes(
        width: input.$1,
        height: input.$2,
        bytes: input.$3.buffer,
        bytesOffset: input.$3.offsetInBytes,
        numChannels: 4,
        order: img.ChannelOrder.rgba));
Uint8List _proceduralPixels((Map<String, dynamic>, Float32List?) input) =>
    socketProceduralPixels(input.$1, input.$2);

/// Same source RGB-gradient and L8-before-ramp semantics as the private oracle.
Uint8List socketProceduralPixels(
    Map<String, dynamic> texture, Float32List? noise) {
  final tree = texture['sourceTree'] as Map,
      props = (texture['sourceTree'] as Map)['properties'] as Map;
  final width = texture['width'] as int, height = texture['height'] as int;
  final gradient = (tree['type'] == 'GradientTexture1D'
      ? props['gradient']['properties']
      : props['color_ramp']['properties']) as Map;
  if ((gradient['interpolation_mode'] ?? 0) != 0 ||
      (gradient['interpolation_color_space'] ?? 0) != 0) {
    throw const FormatException('Unsupported source gradient');
  }
  final values =
      ((gradient['colors']?['values'] as List?) ?? [0, 0, 0, 1, 1, 1, 1, 1])
          .cast<num>();
  final count = values.length ~/ 4;
  final stops = ((gradient['offsets']?['values'] as List?) ??
          List.generate(count, (i) => count == 1 ? 0 : i / (count - 1)))
      .cast<num>();
  if (count == 0 || values.length % 4 != 0 || stops.length != count) {
    throw const FormatException('Invalid source gradient');
  }
  final order = List.generate(count, (i) => i)
    ..sort((a, b) => stops[a].compareTo(stops[b]));
  final result = Uint8List(width * height * 4);
  final float = Float32List(1);
  double f32(double n) {
    float[0] = n;
    return float[0];
  }

  final low = noise?.reduce(math.min) ?? 0, high = noise?.reduce(math.max) ?? 0;
  if (noise != null && noise.length != width * height) {
    throw const FormatException('Invalid source noise size');
  }
  for (var i = 0; i < width * height; i++) {
    var position = width == 1 ? 0.0 : (i % width) / (width - 1);
    if (noise != null) {
      var gray = (props['normalize'] ?? true)
          ? low == high
              ? 0.0
              : f32(f32(f32(noise[i] - low) / f32(high - low)) * 255)
          : f32(f32(noise[i] * 127.5) + 127.5);
      var l8 = gray.clamp(0, 255).toInt();
      if (props['invert'] == true) l8 = 255 - l8;
      position = l8 / 255;
    }
    var left = order.first, right = left;
    if (position > stops[left]) {
      left = right = order.last;
      for (var j = 1; j < order.length; j++) {
        if (position <= stops[order[j]]) {
          left = order[j - 1];
          right = order[j];
          break;
        }
      }
    }
    final t = left == right
        ? 0.0
        : (position - stops[left]) / (stops[right] - stops[left]);
    for (var c = 0; c < 4; c++) {
      final a = values[left * 4 + c], b = values[right * 4 + c];
      result[i * 4 + c] = ((a + (b - a) * t) * 255).toInt().clamp(0, 255);
    }
  }
  return result;
}

class SocketMediaDirectoryBundle extends CachingAssetBundle {
  final Directory directory;
  SocketMediaDirectoryBundle(this.directory);
  static void checkName(String name) {
    if (!RegExp(r'^[a-z0-9_.-]+$').hasMatch(name) ||
        name == '.' ||
        name == '..') {
      throw const FormatException('Invalid imported media filename');
    }
  }

  @override
  Future<ByteData> load(String key) async {
    if (!key.startsWith(SocketMediaModel.assetRoot)) {
      throw const FormatException('Invalid imported media namespace');
    }
    final name = key.substring(SocketMediaModel.assetRoot.length);
    checkName(name);
    return ByteData.sublistView(
        await File('${directory.path}/$name').readAsBytes());
  }
}
