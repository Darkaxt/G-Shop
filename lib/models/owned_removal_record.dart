import 'transfer_record.dart';

enum OwnedRemovalPhase { intent, quarantined, deleting, completed }

/// Explicit user removal, separate from downloading and private-stage cleanup.
/// The immutable manifest is retained as recovery evidence after owner release.
class OwnedRemovalRecord {
  final String id;
  final InstalledArtifact installation;
  final String quarantinePath;
  final OwnedRemovalPhase phase;
  final int revision;
  final String? issue;

  OwnedRemovalRecord(
      {required this.id,
      required this.installation,
      required this.quarantinePath,
      this.phase = OwnedRemovalPhase.intent,
      this.revision = 0,
      this.issue}) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,96}$').hasMatch(id) ||
        !quarantinePath.startsWith('/') ||
        quarantinePath.contains('\\') ||
        quarantinePath.contains('\u0000') ||
        quarantinePath
            .split('/')
            .skip(1)
            .any((p) => p.isEmpty || p == '.' || p == '..') ||
        !RegExp(r'^[A-Za-z0-9_-]{1,96}\.partial$')
            .hasMatch(quarantinePath.split('/').last) ||
        revision < 0 ||
        (issue != null &&
            !RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(issue!))) {
      throw ArgumentError('Invalid owned removal record');
    }
  }

  OwnedRemovalRecord next({OwnedRemovalPhase? phase, String? issue}) =>
      OwnedRemovalRecord(
          id: id,
          installation: installation,
          quarantinePath: quarantinePath,
          phase: phase ?? this.phase,
          revision: revision + 1,
          issue: issue);

  Map<String, dynamic> toJson() => {
        'id': id,
        'installation': installation.toJson(),
        'quarantinePath': quarantinePath,
        'phase': phase.name,
        'revision': revision,
        if (issue != null) 'issue': issue
      };

  factory OwnedRemovalRecord.fromJson(Map<String, dynamic> json) =>
      OwnedRemovalRecord(
          id: json['id'] as String,
          installation: InstalledArtifact.fromJson(
              (json['installation'] as Map).cast<String, dynamic>()),
          quarantinePath: json['quarantinePath'] as String,
          phase: OwnedRemovalPhase.values.byName(json['phase'] as String),
          revision: json['revision'] as int,
          issue: json['issue'] as String?);
}
