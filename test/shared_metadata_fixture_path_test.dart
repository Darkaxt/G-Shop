import 'package:flutter_test/flutter_test.dart';
import 'support/shared_metadata_fixture_path.dart';

void main() {
  test('native proof accepts only a direct shared-storage fixture child', () {
    expect(
        isSharedMetadataProofParent(
            '/storage/emulated/0/RShopSharedProof-20261005-workflow'),
        true);
    expect(
        isSharedMetadataProofParent('/storage/75D7-DC5F/RShopSharedProof-run1'),
        true);
    for (final path in [
      '',
      '/storage/emulated/RShopSharedProof-run',
      '/storage/emulated/1/RShopSharedProof-run',
      '/storage/emulated/0/RShopSharedProof-run/child',
      '/storage/emulated/0/RShopSharedProof-run/../RShopSharedProof-other',
      '/storage/emulated/0/ROMs',
      '/storage/emulated/0/Android/data/RShopSharedProof-run',
      '/storage/unknown/RShopSharedProof-run',
      '/storage/75D7-DC5F/ROMs/RShopSharedProof-run',
    ]) {
      expect(isSharedMetadataProofParent(path), false, reason: path);
    }
  });
}
