"""Restore the approved ImageGen master; Flutter tools generate platform sizes.

Generation provenance and the exact prompt are in docs/GSHOP_ICON_IMAGEGEN.md.
"""
from pathlib import Path
import shutil


def build(root: Path) -> None:
    shutil.copyfile(root / 'assets/branding/gshop-icon-imagegen.png',
                    root / 'assets/icon.png')


if __name__ == '__main__':
    build(Path(__file__).resolve().parents[1])
