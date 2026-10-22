import 'package:collection/collection.dart';
import 'patch_catalogue.dart';

class ResolvedPatchStep {
  final IndexedRomPatch patch;
  final IndexedPatchPayload payload;
  ResolvedPatchStep(this.patch, this.payload);
  PatchRecipeStep get recipeStep => PatchRecipeStep(
      source: patch.source,
      section: patch.section,
      sourceId: patch.sourceId,
      version: patch.version,
      format: payload.format,
      patchSha256: payload.sha256,
      inputSize: patch.requires?.outputSize,
      inputHashes: patch.requires?.outputHashes ?? const {});
}

/// Linear prerequisite chains are resolved by exact public identity and bytes.
/// Different alternatives are never concatenated merely because they share a base.
class PatchChain {
  final List<ResolvedPatchStep> steps;
  PatchChain._(this.steps);
  List<IndexedPatchBase> get bases => steps.first.patch.bases;
  List<PatchRecipeStep> get recipeSteps =>
      steps.map((s) => s.recipeStep).toList();
  factory PatchChain.resolve(List<IndexedRomPatch> available,
      IndexedRomPatch selected, IndexedPatchPayload payload) {
    final ordered = <ResolvedPatchStep>[];
    final visiting = <String>{};
    void visit(IndexedRomPatch patch, IndexedPatchPayload file) {
      if (!patch.payloads.contains(file) || patch.unavailableReason != null) {
        throw const FormatException('patch_unavailable');
      }
      if (!visiting.add(patch.id) || visiting.length > 16) {
        throw const FormatException('patch_dependency_cycle_or_limit');
      }
      final dependency = patch.requires;
      if (dependency != null) {
        final expected = dependency.step;
        final matches = <ResolvedPatchStep>[
          for (final candidate in available)
            if (candidate.source == expected.source &&
                candidate.section == expected.section &&
                candidate.sourceId == expected.sourceId &&
                candidate.version == expected.version)
              for (final value in candidate.payloads)
                if (value.sha256 == expected.patchSha256 &&
                    value.format == expected.format)
                  ResolvedPatchStep(candidate, value)
        ];
        if (matches.length != 1) {
          throw const FormatException('patch_dependency_missing_or_ambiguous');
        }
        visit(matches.single.patch, matches.single.payload);
      }
      ordered.add(ResolvedPatchStep(patch, file));
    }

    visit(selected, payload);
    return PatchChain._(List.unmodifiable(ordered));
  }
  void requireBase(IndexedPatchBase base) {
    if (!bases.any((value) =>
        const DeepCollectionEquality().equals(value.content, base.content))) {
      throw const FormatException('patch_chain_base_mismatch');
    }
  }
}
