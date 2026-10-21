# NES private media conversion

2026-10-21, ICON-01 / NES-01..05. Native and final-release verification is pending.

| Resource | Converted and import-verified | Binding |
| --- | ---: | --- |
| Expanded collector scene | 340 mesh objects; all 291 original nodes/placements preserved | NES console selector default |
| Supplied console scenes | Front loader, NES-101, Nintendo Famicom, Dendy-compatible clone | Explicit hardware menu |
| NintAndBox cartons | All 623 supplied NES/Famicom editions | Private edition IDs and manifest hashes |
| Cartridge variants | 23 supplied, plus retained Aladdin reference | Physical family and explicit reference choice |
| Additional references | Six PCB templates and one dust sleeve | Explicit reference choice |

The collector scene retains Rusty Hardy's attribution and original licence in its
private manifest. Its original GLB and props are preserved. Three further consoles
retain their own controller/cable arrangements in a shallow arc. The bounded
conversion has 143,081 triangles, 77 material surfaces and 91 textures. Individual
console imports retain their supplied credits and recorded licence limitations.
Original third-party models and game artwork are not bundled
with the application or published in this repository.

Every carton retains its actual opening hinges and source Open/Close timing.
Conversion checks the sampled runtime articulation against the GLB, with maximum
error below 0.0001. Production loaders also check mesh and texture checksums.
All 623 editions are deployed, including printings not currently bound to a ROM.
The newer supplied delivery's 34 GLBs independently pass Khronos validation with
zero errors and warnings, and all 92 delivery-manifest checksums match. All 23
cartridge variants retain their Explode/Assemble inspection motion; converted
translations agree with Blender's evaluated poses within 0.0001. Front artwork
uses each model's UV dimensions; rear caution labels remain separate. Transparent
inspection aids and illustrative PCBs are explicitly distinguished from retail
editions. Famicom-compatible bootleg donor atlases remain their authored references.

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
Regional console markings and Sharp TV remain additional coverage. Supplied pale,
service/FamicomBox and inspection references are available explicitly, without
automatically assigning those physical editions to a ROM.

Private census, per-file conversion/transfer receipts, reference photographs and
renders remain under D:/Temp/gshop-nes-20261021/reports. Reusable authored sources
and runtime imports are intentionally retained alongside that report directory.
The initial device placement preserved every path/hash of the 1,203 previous
imports. Supplied-model replacement, the requested per-game carton/sleeve/cartridge
unboxing and final native/public delivery acceptance remain pending.
