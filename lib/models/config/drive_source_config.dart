/// Stable, credential-free configuration for a Google Drive source.
///
/// OAuth access tokens are intentionally absent. They are resolved from the
/// native authorization session at request time and must never be serialized
/// into the app config, catalogue, exports, or download queue.
class DriveSourceConfig {
  /// Stable Google account identifier returned by native sign-in.
  final String accountId;

  /// Actual Drive folder ID selected by the user (never the `root` alias).
  final String rootFolderId;

  /// Public Web OAuth client ID configured for this fork.
  final String serverClientId;

  const DriveSourceConfig({
    required this.accountId,
    required this.rootFolderId,
    required this.serverClientId,
  });

  factory DriveSourceConfig.fromJson(Map<String, dynamic> json) {
    return DriveSourceConfig(
      accountId: json['account_id'] as String? ?? '',
      rootFolderId: json['root_folder_id'] as String? ?? '',
      serverClientId: json['server_client_id'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'account_id': accountId,
      'root_folder_id': rootFolderId,
      'server_client_id': serverClientId,
    };
  }

  bool get isConfigured =>
      accountId.trim().isNotEmpty &&
      rootFolderId.trim().isNotEmpty &&
      serverClientId.trim().isNotEmpty;

  DriveSourceConfig copyWith({
    String? accountId,
    String? rootFolderId,
    String? serverClientId,
  }) {
    return DriveSourceConfig(
      accountId: accountId ?? this.accountId,
      rootFolderId: rootFolderId ?? this.rootFolderId,
      serverClientId: serverClientId ?? this.serverClientId,
    );
  }
}
