import '../models/config/provider_config.dart';
import 'providers/drive_provider.dart';
import 'source_provider.dart';

class ProviderFactory {
  static SourceProvider getProvider(ProviderConfig config) {
    if (config.type != ProviderType.drive) {
      throw UnsupportedError(
          'G-Shop supports Google Drive collection sources only');
    }
    return DriveProvider(config);
  }
}
