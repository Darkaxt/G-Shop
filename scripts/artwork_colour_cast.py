"""Estimate a single global scan cast before publishing replacement artwork."""
import numpy as np
from PIL import Image, ImageFilter


def match_colour_cast(source, reference):
    """Fit one RGB affine correction from corresponding cover regions.

    Small, blurred samples suppress print grain. Robust palette anchors keep
    changed regional text from defining the cast; the dominant colour has the
    greatest weight. A held-out spatial sample must corroborate the correction.
    No geometric warp or reference pixels are copied to the replacement.
    """
    original = source.convert('RGBA')
    def unchanged(reason, **details):
        return original, {'applied': False, 'reason': reason, **details}

    def sample(image):
        return np.asarray(image.convert('RGBA').resize((64, 64),
            Image.Resampling.LANCZOS).filter(ImageFilter.GaussianBlur(.7)), dtype=float) / 255

    a, b = sample(source), sample(reference)
    valid = (a[:, :, 3] > .98) & (b[:, :, 3] > .98)
    if np.count_nonzero(valid) < 256:
        return unchanged('insufficient-opaque-art')
    yy, xx = np.indices(valid.shape)
    train, check = valid & ((xx + yy) % 2 == 0), valid & ((xx + yy) % 2 == 1)
    before = float(np.median(np.linalg.norm(a[check, :3] - b[check, :3], axis=1)))
    if before < .02:
        return unchanged('already-matched')
    # Correspondence, not independently sorted palettes: a title's blue cannot
    # accidentally be paired with an unrelated image's similarly common red.
    x, y = a[train, :3], b[train, :3]
    bins = np.floor(x * 15).astype(int)
    keys, inverse, counts = np.unique(bins, axis=0, return_inverse=True, return_counts=True)
    anchors = [i for i, count in enumerate(counts) if count >= 4]
    if len(anchors) < 8:
        return unchanged('insufficient-colour-anchors')
    sx = np.array([np.median(x[inverse == i], axis=0) for i in anchors])
    sy = np.array([np.median(y[inverse == i], axis=0) for i in anchors])
    weight = np.array([counts[i] for i in anchors], dtype=float)
    # A dominant blue background must not redefine white paper as cyan. Both
    # scans' actual bright neutral print corroborates the same global transform;
    # this is a fitting anchor, never a separate pixel mask or selective repaint.
    def paper(samples):
        mask = (samples.min(axis=1) > .8) & (np.ptp(samples, axis=1) < .12)
        return np.median(samples[mask], axis=0) if np.count_nonzero(mask) >= 32 else None
    source_paper, reference_paper = paper(x), paper(y)
    if source_paper is not None and reference_paper is not None:
        sx = np.vstack([sx, source_paper])
        sy = np.vstack([sy, reference_paper])
        weight = np.append(weight, len(x) * 2)
    design = np.column_stack([sx, np.ones(len(sx))])
    if np.linalg.matrix_rank(design) < 4:
        return unchanged('insufficient-colour-range')
    robust = np.ones(len(sx))
    for _ in range(6):
        w = np.sqrt(weight * robust)[:, None]
        matrix = np.linalg.lstsq(design * w, sy * w, rcond=None)[0]
        residual = np.linalg.norm(design @ matrix - sy, axis=1)
        scale = max(.015, float(np.median(residual)) * 1.5)
        robust = np.minimum(1, scale / np.maximum(residual, 1e-9))
    if not np.isfinite(matrix).all() or np.max(np.abs(matrix)) > 8 or np.linalg.det(matrix[:3]) <= 0:
        return unchanged('unstable-colour-transform')
    observed = np.column_stack([a[check, :3], np.ones(np.count_nonzero(check))])
    after = float(np.median(np.linalg.norm(np.clip(observed @ matrix, 0, 1) - b[check, :3], axis=1)))
    # Regional text/layout and print grain differ; allow a median 0.18 RGB-vector
    # distance (~26 levels per channel), but require at least 20% improvement.
    if after > .18 or after > before * .8:
        return unchanged('cast-not-corroborated', errorBefore=before, errorAfter=after)
    pixels = np.asarray(original).copy()
    rgb = pixels[:, :, :3].astype(float) / 255
    pixels[:, :, :3] = np.round(np.clip(rgb @ matrix[:3] + matrix[3], 0, 1) * 255).astype(np.uint8)
    return Image.fromarray(pixels), {
        'applied': True, 'method': 'rgb-affine-v1',
        'matrix': matrix.tolist(), 'errorBefore': before, 'errorAfter': after,
        'anchors': len(anchors), 'dominantSamples': int(max(counts)),
    }
