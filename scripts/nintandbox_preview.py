"""Classify the public joined-sheet preview using its actual fold boundaries."""
import io
import numpy as np
from PIL import Image
from prepare_unfolded_boxes import locate_fold_panel
from prepare_packaging_resources import fit_panel, png


def split_preview(body):
    with Image.open(io.BytesIO(body)) as image:
        if image.width > 1600 or image.height > 1600:
            raise ValueError('Expected the public low-resolution preview')
        located = locate_fold_panel(image, 1.0, joined=True)
        if located is None:
            return []
        (x, y, w, h), _ = located
        row = np.array(image.convert('RGB'))[y + h // 2]
        nonwhite = np.flatnonzero(np.min(row[:x], axis=1) < 244)
        if not len(nonwhite):
            return []
        depth = x - int(nonwhite.min())
        back_x = x + w + depth
        if not .07 * h < depth < .3 * h or back_x + w > image.width or y + h + depth > image.height:
            return []
        definitions = {'front': ([x, y, w, h], 0, w / h),
            'back': ([back_x, y, w, h], 0, w / h),
            'left': ([x - depth, y, depth, h], 0, depth / h),
            'right': ([x + w, y, depth, h], 0, depth / h),
            'top': ([back_x, y - depth, w, depth], 180, w / depth),
            'bottom': ([back_x, y + h, w, depth], 0, w / depth)}
        parts = []
        for role, (crop, rotation, aspect) in definitions.items():
            a, b, width, height = crop
            part = image.crop((a, b, a + width, b + height))
            if rotation:
                part = part.rotate(-rotation, expand=True)
            part = fit_panel(part, aspect)
            output = io.BytesIO()
            part.save(output, format='PNG')
            parts.append((role, png(output.getvalue()), crop, rotation))
        return parts
