import 'package:flutter_test/flutter_test.dart';
import 'package:g_shop/models/config/drive_source_config.dart';
import 'package:g_shop/models/config/source.dart';
import 'package:g_shop/providers/source_health_providers.dart';
import 'package:g_shop/services/source_provider.dart';

void main() {
  test('Drive health is checked without producing auto-map platforms',
      () async {
    var checks = 0;
    final notifier = SourceHealthNotifier(
      driveHealthCheck: (source) async {
        checks++;
        expect(source.type, SourceType.drive);
        return const SourceConnectionResult.ok();
      },
    );
    const source = Source(
      id: 'drive-source',
      name: 'Drive',
      type: SourceType.drive,
      autoMap: false,
      drive: DriveSourceConfig(
        accountId: 'account',
        rootFolderId: 'root-id',
        serverClientId: 'client-id',
      ),
    );

    final discovered = await notifier.checkAll(const [source]);

    expect(checks, 1);
    expect(notifier.state.statusFor(source.id), SourceHealth.valid);
    expect(discovered, isEmpty);

    notifier.markUnknown([source.id]);
    expect(notifier.state.statusFor(source.id), SourceHealth.unknown);
    expect(notifier.state.errorFor(source.id), isNull);
  });

  test('sanitized Drive setup failure becomes invalid health', () async {
    final notifier = SourceHealthNotifier(
      driveHealthCheck: (_) async => const SourceConnectionResult.failed(
          'Drive authorization: setupRequired'),
    );

    await notifier.checkAll(const [
      Source(
        id: 'drive-source',
        name: 'Drive',
        type: SourceType.drive,
      ),
    ]);

    expect(notifier.state.statusFor('drive-source'), SourceHealth.invalid);
    expect(
      notifier.state.errorFor('drive-source'),
      'Drive authorization: setupRequired',
    );
  });
}
