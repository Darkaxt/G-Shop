import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/models/scraped_metadata.dart';
import 'package:g_shop/services/metadata/es_de_metadata_projection.dart';

void main() {
  test('release selection uses exact edition region, not first provider row',
      () {
    const dates = [
      MetadataText(text: '1997-01-01', region: 'jp'),
      MetadataText(text: '1998-02-03', region: 'us')
    ];
    expect(selectEditionReleaseDate(dates, regions: ['USA']), '1998-02-03');
    expect(selectEditionReleaseDate(dates, regions: ['Europe']), isNull);
    expect(selectEditionReleaseDate(dates, regions: ['USA', 'Japan']), isNull);
    expect(
        selectEditionReleaseDate(
            [...dates, const MetadataText(text: '1999-03-04')],
            regions: ['Europe']),
        '1999-03-04');
    expect(
        selectEditionReleaseDate(
            [const MetadataText(text: '1998-02-31', region: 'us')],
            regions: ['USA']),
        isNull);
    expect(EsDeMetadataProjection.releaseDate('1998-02-03'), '19980203T000000');
    expect(EsDeMetadataProjection.releaseDate('1998'), isNull);
    expect(EsDeMetadataProjection.releaseDate('1998-02'), isNull);
    expect(EsDeMetadataProjection.releaseDate('1998-02-31'), isNull);
  });
}
