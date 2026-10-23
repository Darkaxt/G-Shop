/// Portable provider credentials; storage remains host-specific.
class ScreenScraperDeveloperCredentials {
  final String developerId;
  final String developerPassword;
  final String softwareName;
  const ScreenScraperDeveloperCredentials(
      {required this.developerId,
      required this.developerPassword,
      required this.softwareName});
  bool get isConfigured =>
      developerId.trim().isNotEmpty &&
      developerPassword.trim().isNotEmpty &&
      softwareName.trim().isNotEmpty;
  @override
  String toString() => 'ScreenScraperDeveloperCredentials(redacted)';
}

class ScreenScraperUserCredentials {
  final String username;
  final String password;
  const ScreenScraperUserCredentials(
      {required this.username, required this.password});
  bool get isConfigured =>
      username.trim().isNotEmpty && password.trim().isNotEmpty;
  @override
  String toString() => 'ScreenScraperUserCredentials(redacted)';
}

class MetadataCredentialStorageException implements Exception {
  const MetadataCredentialStorageException();
  @override
  String toString() => 'Metadata credentials could not be accessed securely.';
}
