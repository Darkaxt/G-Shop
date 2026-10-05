import 'package:path/path.dart' as p;

bool isSharedMetadataProofParent(String path) =>
    p.posix.normalize(path) == path &&
    RegExp(r'^/storage/(?:emulated/0|[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4})/RShopSharedProof-[a-zA-Z0-9-]+$')
        .hasMatch(path);
