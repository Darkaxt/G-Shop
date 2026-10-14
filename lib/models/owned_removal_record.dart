import 'transfer_record.dart';

enum OwnedRemovalPhase { intent, quarantined, deleting, completed, retained }

/// Explicit user removal, separate from downloading and private-stage cleanup.
/// The immutable manifest is retained as recovery evidence after owner release.
class OwnedRemovalRecord {
  final String id;
  final InstalledArtifact installation;
  final String quarantinePath;
  final OwnedRemovalPhase phase;
  final int revision;
  final String? issue;
  final bool policyDriven;
  final List<InstalledArtifact> groupMembers;
  final String? parentRemovalId;

  bool get isTerminal =>
      phase == OwnedRemovalPhase.completed ||
      phase == OwnedRemovalPhase.retained;

  OwnedRemovalRecord(
      {required this.id,
      required this.installation,
      required this.quarantinePath,
      this.phase = OwnedRemovalPhase.intent,
      this.revision = 0,
      this.issue,
      this.policyDriven = false,
      this.parentRemovalId,
      List<InstalledArtifact> groupMembers = const []})
      : groupMembers = List.unmodifiable(groupMembers) {
    if (groupMembers.length > 256 ||
        groupMembers.any((m) =>
            m.id == installation.id ||
            m.destinationRoot != installation.destinationRoot) ||
        groupMembers.map((m) => m.id).toSet().length != groupMembers.length) {
      throw ArgumentError('Invalid removal game group');
    }
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
          issue: issue,
          policyDriven: policyDriven,
          groupMembers: groupMembers,
          parentRemovalId: parentRemovalId);

  Map<String, dynamic> toJson() => {
        'id': id,
        'installation': installation.toJson(),
        'quarantinePath': quarantinePath,
        'phase': phase.name,
        'revision': revision,
        if (issue != null) 'issue': issue,
        if (policyDriven) 'policyDriven': true,
        if (groupMembers.isNotEmpty)
          'groupMembers': [for (final m in groupMembers) m.toJson()],
        if (parentRemovalId != null) 'parentRemovalId': parentRemovalId,
      };

  factory OwnedRemovalRecord.fromJson(Map<String, dynamic> json) =>
      OwnedRemovalRecord(
          id: json['id'] as String,
          installation: InstalledArtifact.fromJson(
              (json['installation'] as Map).cast<String, dynamic>()),
          quarantinePath: json['quarantinePath'] as String,
          phase: OwnedRemovalPhase.values.byName(json['phase'] as String),
          revision: json['revision'] as int,
          issue: json['issue'] as String?,
          policyDriven: json['policyDriven'] as bool? ?? false,
          parentRemovalId: json['parentRemovalId'] as String?,
          groupMembers: [
            for (final m in json['groupMembers'] as List? ?? const [])
              InstalledArtifact.fromJson((m as Map).cast<String, dynamic>())
          ]);
}
