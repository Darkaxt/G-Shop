import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/system_model.dart';
import '../../../providers/installed_files_provider.dart';
import '../../../widgets/media_cover_fallback.dart';
import 'library_entry.dart';

/// Cached catalogue statistics, not canonical identity or eviction evidence.
class LibraryConsoleSummary {
  final String slug;
  final int entries, installed, downloadable, favorites;
  final int sourceBytes, knownSourceSizes, unknownSourceSizes;
  final int? managedBytes;

  const LibraryConsoleSummary(
      {required this.slug,
      required this.entries,
      required this.installed,
      required this.downloadable,
      required this.favorites,
      required this.sourceBytes,
      required this.knownSourceSizes,
      required this.unknownSourceSizes,
      required this.managedBytes});

  static List<LibraryConsoleSummary> fromEntries(List<LibraryEntry> entries,
      {required bool Function(LibraryEntry) isInstalled,
      required Set<String> favorites,
      required InstalledFilesState installation}) {
    final groups = <String, Map<String, LibraryEntry>>{};
    for (final entry in entries) {
      (groups[entry.systemSlug] ??= {})[entry.selectionKey] = entry;
    }
    final result = <LibraryConsoleSummary>[];
    for (final group in groups.entries) {
      var local = 0,
          remote = 0,
          favorite = 0,
          bytes = 0,
          known = 0,
          unknown = 0;
      for (final entry in group.value.values) {
        if (isInstalled(entry)) local++;
        if (favorites.contains(entry.selectionKey)) favorite++;
        if (entry.hasDownloadSource) remote++;
        if (entry.remoteArtifact != null || entry.hasDownloadSource) {
          final size = entry.remoteArtifact?.sizeBytes;
          if (size == null) {
            unknown++;
          } else {
            bytes += size;
            known++;
          }
        }
      }
      result.add(LibraryConsoleSummary(
          slug: group.key,
          entries: group.value.length,
          installed: local,
          downloadable: remote,
          favorites: favorite,
          sourceBytes: bytes,
          knownSourceSizes: known,
          unknownSourceSizes: unknown,
          managedBytes: installation.managedBytesBySystem[group.key]));
    }
    result.sort((a, b) => consoleName(a.slug).compareTo(consoleName(b.slug)));
    return result;
  }

  static String consoleName(String slug) =>
      SystemModel.supportedSystems
          .where((s) => s.id == slug)
          .firstOrNull
          ?.name ??
      slug;
}

String libraryStorageSize(int bytes) {
  const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
  var value = bytes.toDouble(), unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${unit == 0 ? bytes : value.toStringAsFixed(1)} ${units[unit]}';
}

class LibraryConsoleCard extends StatelessWidget {
  final LibraryConsoleSummary summary;
  final bool selected;
  final VoidCallback onTap;
  const LibraryConsoleCard(
      {super.key,
      required this.summary,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final accent = SystemModel.supportedSystems
            .where((s) => s.id == summary.slug)
            .firstOrNull
            ?.accentColor ??
        Colors.cyanAccent;
    final sourceSize = summary.knownSourceSizes == 0
        ? (summary.unknownSourceSizes == 0
            ? libraryStorageSize(0)
            : l.library_sizeUnknown)
        : libraryStorageSize(summary.sourceBytes);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color:
            selected ? accent.withValues(alpha: 0.12) : const Color(0xFF11191C),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
                color: selected ? accent : Colors.white12,
                width: selected ? 2 : 1)),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Image.asset(mediaFallbackAsset(summary.slug),
                        width: 44,
                        height: 44,
                        fit: BoxFit.contain,
                        excludeFromSemantics: true),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text(
                            LibraryConsoleSummary.consoleName(summary.slug),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700))),
                    Icon(Icons.chevron_right_rounded, color: accent),
                  ]),
                  const SizedBox(height: 12),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                        child: _metric(
                            l.library_catalogueEntries, '${summary.entries}')),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _metric(
                            l.library_tabInstalled, '${summary.installed}')),
                  ]),
                  const SizedBox(height: 8),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                        child: _metric(l.gameCard_cloudAvailable,
                            '${summary.downloadable}')),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _metric(
                            l.library_tabFavorites, '${summary.favorites}')),
                  ]),
                  const Divider(color: Colors.white12, height: 24),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                        child: _storage(l.library_sourceStorage, sourceSize,
                            'source-size')),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _storage(
                            l.library_managedStorage,
                            summary.managedBytes == null
                                ? l.library_sizeUnknown
                                : libraryStorageSize(summary.managedBytes!),
                            'managed-size')),
                  ]),
                  if (summary.unknownSourceSizes > 0)
                    Text(l.library_unknownSizes(summary.unknownSourceSizes),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white60, fontSize: 12)),
                ]),
          ),
        ),
      ),
    );
  }

  Widget _metric(String label, String value) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700)),
            Tooltip(
                message: label,
                child: Text(label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(color: Colors.white60, fontSize: 12)))
          ]);

  Widget _storage(String label, String value, String key) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Tooltip(
            message: label,
            child: Text(label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white60, fontSize: 12))),
        Text(value,
            key: ValueKey(key),
            style: const TextStyle(color: Colors.white, fontSize: 14)),
      ]);
}
