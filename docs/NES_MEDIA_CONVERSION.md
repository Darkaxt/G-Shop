# NES private media conversion

2026-10-21, ICON-01 / NES-01..05. Native and final-release verification is pending.

| Resource | Converted and import-verified | Binding |
| --- | ---: | --- |
| Supplied collector scene | 1, all 290 authored objects retained | NES console selector default |
| Console bodies | Front loader and NES-101 with dogbone | Explicit hardware menu |
| NintAndBox cartons | All 623 supplied NES/Famicom editions | Private edition IDs and manifest hashes |
| Cartridge reference styles | 13 | Physical family, region and release classification |

The collector scene retains Rusty Hardy's attribution and original licence in its
private manifest. Its original GLB is preserved; display conversion reduces
875,527 triangles to 128,821, retaining placements, 54 material surfaces and 33
bounded textures. Original third-party models and game artwork are not bundled
with the application or published in this repository.

Every carton retains its actual opening hinges and source Open/Close timing.
Conversion checks the sampled runtime articulation against the GLB, with maximum
error below 0.0001. Production loaders also check mesh and texture checksums.
All 623 editions are deployed, including printings not currently bound to a ROM.

The owner's 9,831 NES archives yield 453 same-region reference-box bindings, 71
with multiple available printings. 6,220 archives are excluded as tagged hacks,
aftermarket, prototypes, demos or other non-retail forms; another 3,158 have no
compatible reference binding. That last group includes Japanese/Famicom and other
special releases, so it must not be described as 3,158 missing NES retail boxes.
**No exact owned physical printing has been established from ROM identity.**

1,219 archives have one or more known NES cartridge-family references. Styles
include three/five-screw grey/gold Nintendo, black Tengen, gold/silver Camerica,
blue/black Color Dreams family, square/clipped AVE, clear Active Enterprises and
Aladdin adapter with a separate compact cartridge. PCB/components are illustrative;
nonstandard proportions follow photographs rather than engineering measurements.
Famicom, unknown unlicensed, modern aftermarket and hacked releases do not silently
inherit a grey 72-pin cartridge. Zelda revisions and fixed Camerica colours retain
their documented distinctions; ambiguous physical editions remain labelled choices.

References: [cartridge revisions](https://www.thelegendofnes.com/cartridge-design),
[console hardware](https://www.thelegendofnes.com/ntsc-pal),
[Camerica](https://www.thelegendofnes.com/unlicensed-games/camerica),
[AVE](https://www.thelegendofnes.com/unlicensed-games/american-video-entertainment),
[Tengen](https://www.thelegendofnes.com/unlicensed-games/tengen).
Regional console markings, pale Asian shells, Sharp TV and non-retail cartridges
are separate additional coverage, not invented missing meshes for this batch.

Private census, per-file conversion/transfer receipts, reference photographs and
renders remain under D:/Temp/gshop-nes-20261021/reports. Reusable authored sources
and runtime imports are intentionally retained alongside that report directory.
Device placement verified 5,637 new files and preserved every path/hash of the
1,203 previous imports. No user library, source mapping or original asset was moved.
