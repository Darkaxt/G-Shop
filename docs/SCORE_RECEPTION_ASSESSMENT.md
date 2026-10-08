# Live overall-score assessment — 2026-10-03

Authority: SPECIFICATION.md, META-05. Initial assessment owner: S4 (closed).
The collection-scope extension below belongs to ACTIVE S7. Current stage state
is in IMPLEMENTATION_STATUS.md. Source assessment is not whole-stage closure.

## Wii/Wii U collection-scope assessment — 2026-10-09

The existing opt-in serial public IGDB persistent-worker benchmark captured ten
original Wii/Wii U releases at 22:26:47–22:26:52 UTC on 2026-10-08. All ten
literal offered titles/platform-checked identities were explicitly reviewed in
the public fixture. Original Skyward Sword, Mario Kart 8 and Xenoblade Chronicles
X records were used, not HD/Deluxe/Definitive editions, bundles, DLC or projects.
This is not a production title-only classification rule or a private-library
identity correction. No ROM body, artwork, device job or private library was
read or changed. The first offline query correctly ranked zero because these
scopes were not yet assessed; receiving scores does not itself approve them.

| Platform / original release | IGDB ID | Community / votes | Support |
| --- | ---: | ---: | --- |
| Wii / Super Mario Galaxy | 1077 | 88.71 / 1,303 | Supported |
| Wii / The Legend of Zelda: Skyward Sword | 534 | 81.89 / 399 | Supported |
| Wii / Wii Sports | 2181 | 75.20 / 441 | Supported |
| Wii / Red Steel | 2258 | 56.70 / 31 | Supported; modest sample |
| Wii / Ninjabread Man | 5077 | 65.19 / 5 | Too few votes |
| Wii U / Super Mario 3D World | 2180 | 84.34 / 435 | Supported |
| Wii U / Mario Kart 8 | 2350 | 86.56 / 675 | Supported |
| Wii U / Xenoblade Chronicles X | 2366 | 80.90 / 76 | Supported |
| Wii U / Devil's Third | 7395 | 64.99 / 6 | Too few votes |
| Wii U / Sonic Boom: Rise of Lyric | 5322 | 15.90 / 33 | Supported low band; material numerical disagreement |

Independent original-platform Nintendo Life community evidence was inspected
on 2026-10-09 (local date):
[Galaxy](https://www.nintendolife.com/games/wii/super_mario_galaxy) 9.1/10 from
2,621 users;
[Skyward Sword](https://www.nintendolife.com/games/wii/legend_of_zelda_skyward_sword)
8.4 from 1,115;
[Wii Sports](https://www.nintendolife.com/games/wii/wii_sports) 8.2 from 846; and
[Red Steel](https://www.nintendolife.com/games/wii/red_steel) 6.6 from 122. The
high-to-middle ordering agrees, not identical values or voting populations.
[Ninjabread Man](https://www.nintendolife.com/games/wii/ninjabread_man) is 3.4
from twelve users (its editorial review is 2/10). IGDB's five-vote 65.19 is
inconsistent with that low reception; the unchanged vote floor excludes it.
No other provider's votes are borrowed to rescue that score.

For Wii U,
[3D World](https://www.nintendolife.com/games/wiiu/super_mario_3d_world) is 8.5
from 2,344 users;
[Mario Kart 8](https://www.nintendolife.com/games/wiiu/mario_kart_8) 8.8 from
1,250; and
[Xenoblade X](https://www.nintendolife.com/games/wiiu/xenoblade_chronicles_x)
8.5 from 748. These support the high band, not an identical ordering of the two
nearby Mario games. [Devil's Third](https://www.nintendolife.com/games/wiiu/devils_third)
is 6.8 from 49, but agreement cannot qualify IGDB's six-vote record.

[Sonic Boom](https://www.nintendolife.com/games/wiiu/sonic_boom_rise_of_lyric)
is 3.5 from 326 users;
[Metacritic's original Wii U page](https://www.metacritic.com/game/sonic-boom-rise-of-lyric/)
reports users 3.7/10 from 790 and critics 32/100 from 28. IGDB's community
15.90 from 33 is substantially lower, while its separately returned critics
37.5 from four and blended total 26.70 from 37 are distinct measures. All
independent measures place this release in the low band; the discrepancy does
not reverse its relationship to the supported high/middle examples. This
resolves the source-selection question in favor of the already assessed,
explicitly labelled IGDB-user basis, not numerical interchangeability with
other communities. No evidence explains individual voting behavior, proves
fine-grained consensus ranks or makes the twenty-vote floor a confidence
interval. Preserve the real score/count and this limitation, rather than
switching to critics/total, blending, adjusting this title or inventing votes.

Decision: extend the existing game-level IGDB community basis to `wii` and
`wiiu`. The S4 representative assessment remains the foundation; this checks
two current recovery/collection scopes without inventing a new estimator.
Scale, deterministic precedence, twenty-known-user-vote minimum, current exact
identity, score ownership, freshness, grouping and provisional coverage rules
are unchanged. Unknown/modified editions do not become official; a game-level
record is not a console-specific critic aggregate. The benchmark includes a
sports release to assess the provider, not to revise archival/device Top rules.
Game Gear and other unassessed scopes remain unapproved. This is not defensible
whole-collection retention, current-cloud proof or SD-removal authority.

Verification: the support-boundary regression first failed for Wii with twenty
votes before the policy extension. The affected effective-score and real SQLite
query checks now pass, including cached policy re-projection without rescraping,
nineteen-vote rejection, unresolved-game preservation and provisional retention.
Scoped Dart analysis and diff checks pass. A second serial public-provider
capture at 22:29:54–22:29:59 UTC on 2026-10-08 matched the same ten releases;
after closing its network adapter, the production offline query ranked eight,
excluded both sparse-vote records and reported provisional coverage. No other
provider score was substituted. Native integration is pending: the installed
app still runs its existing root refresh and saved metadata job 76, and no build
or device installation was performed for this policy change.

## NES/SNES collection-scope assessment — 2026-10-07

The existing serial public persistent-worker benchmark captured ten original
NES/SNES releases at 14:24:29–14:25:37 UTC. Exact offered titles/platform IDs were
explicitly reviewed in the public fixture; this is not a new automatic library
classification rule. The two initial punctuation mismatches were corrected to
the actual offered titles, without adding a production alias/retry mechanism.
The existing META-05 representative assessment remains the foundation. This
extension assesses two actual S7 collection scopes, not a new estimator.

| Platform / original release | IGDB ID | Actual community / votes | Support |
| --- | ---: | ---: | --- |
| NES / Super Mario Bros. 3 | 1068 | 89.36 / 1,740 | Supported |
| NES / Mega Man 2 | 1715 | 85.17 / 390 | Supported |
| NES / Castlevania II: Simon's Quest | 1116 | 61.88 / 148 | Supported; different communities disagree |
| NES / Dr. Jekyll and Mr. Hyde | 7961 | 17.72 / 17 | Too few votes |
| NES / Action 52 | 5340 | 19.34 / 10 | Too few votes; original unlicensed multicart, not a hack |
| SNES / Super Mario World | 1070 | 91.69 / 2,043 | Supported |
| SNES / Chrono Trigger | 1802 | 93.25 / 1,393 | Supported |
| SNES / Super Ghouls'n Ghosts | 6621 | 74.36 / 94 | Supported; not Restoration |
| SNES / Shaq-Fu | 8536 | 40.23 / 20 | Supported at the unchanged floor |
| SNES / Super James Pond | 4443 | 64.78 / 32 | Supported game-level record; not a SNES-specific average |

Independent original-platform evidence inspected on 2026-10-07:
[NES Mario 3](https://gamefaqs.gamespot.com/nes/525245-super-mario-bros-3/stats)
4.54/5 from 6,769 users and
[NES Mega Man 2](https://gamefaqs.gamespot.com/nes/563442-mega-man-2/stats)
4.26/5 from 3,032 support high reception. Nintendo Life's own
[NES Castlevania II community](https://www.nintendolife.com/reviews/vc/castlevania_ii_simons_quest_nes)
6.7/10 from 123 users corroborates IGDB's middle band. The
[GameSpot NES/FDS hub](https://www.gamespot.com/games/castlevania-ii-simons-quest/reviews/)
instead reports 7.9/10 from 1,413 users, a material difference. Its pooled hub and
different voters are not the same sample; Nintendo Life's NES-specific community
and GameSpot's individual NES 6.5 review corroborate the lower band. This resolves
the source-selection question in favor of the labelled community basis, not a
claim that all communities agree, a causal explanation of every vote, or a
title-specific adjustment. No independent count is attached to IGDB.

[NES Dr. Jekyll](https://gamefaqs.gamespot.com/nes/563406-dr-jekyll-and-mr-hyde/stats)
1.15/5 from 333 supports low reception but cannot rescue IGDB's seventeen votes.
[SNES Mario World](https://gamefaqs.gamespot.com/snes/519824-super-mario-world/stats)
4.54/5 from 8,253 and
[SNES Chrono Trigger](https://gamefaqs.gamespot.com/snes/563538-chrono-trigger/stats)
4.55/5 from 7,250 support high reception; GBA/PC/PS/mobile ports were not used.
[SNES Ghouls](https://gamefaqs.gamespot.com/snes/588732-super-ghouls-n-ghosts/stats)
3.7/5 from 949 agrees with 74.36/100. GameFAQs' own
[SNES Shaq-Fu review](https://gamefaqs.gamespot.com/snes/588653-shaq-fu/reviews/24205)
5/10 is one individual review, not a consensus target; it supports a lower band
relative to the acclaimed examples. No inaccessible aggregate page or Genesis
review was substituted. Its twenty-vote IGDB sample meets the existing floor,
not a statistical confidence guarantee. GameFAQs identifies
[Super James Pond](https://gamefaqs.gamespot.com/snes/588736-super-james-pond)
as James Pond II/RoboCod and labels its 51-user reception Fair. That corroborates
middle reception and the alias identity, not numerical equality with a global
multiplatform average. Unsupported aggregate evidence for Action 52 was not
invented; the ten-vote score remains excluded regardless of its extreme value.

Decision: extend the existing assessed IGDB community basis to `nes`/`snes` with
unchanged 0–100 scale, precedence, twenty-known-vote minimum, current bound
identity/ownership and freshness rules. Never substitute blended totals (Mario
World's one-critic total is 95.85), critic counts or scores from another port.
Projects, ambiguous identities and unreviewed classifications remain separate.
This public assessment does not complete collection coverage, establish a
defensible whole-collection Top-25, or grant SD removal authority. The initial
offline production query correctly ranked zero until this scope was assessed.

Verification: the focused support-boundary test failed at NES/twenty votes before
extension and passed afterwards. The existing effective-score and indexed-query
checks passed, including provisional retention, stale/unknown/low counts and
project ownership. A fresh real-provider capture at 14:33:24–14:33:29 UTC returned
the same score/count evidence; after closing its network adapter, the production
cached/offline query selected eight supported canonical games from ten fixtures,
with identical Top-25 membership and explicitly provisional coverage. Scoped
Dart analysis and diff checks passed. Native integration remains current S7
work until the updated ordinary APK is built and verified; it is not inferred
from this host evidence.

## Decision

ScreenScraper's current `note` is usable as a labelled, sourced advisory score,
but this assessment **does not approve it as the consensus basis for Top-N**.
The original ScreenScraper pass did not enable a score policy. The subsequent
IGDB assessment below accepts its sourced game-level **community** average within
the recorded scope and support threshold, not its blended total or critic score.

The live adapter preserved a 0–20 scale, normalized linearly to 0–100, with
`unknownAggregate`, unknown vote count and `consensusValidated=false` for every
retrieved sample. The [API documentation](https://www.screenscraper.fr/webapi2.php)
documents the scale, but does not establish the returned score's aggregation
method or sample size. A documented member-rating submission endpoint alone
does not establish how a returned aggregate was calculated.

The sample shows both broad agreement and material differences from independent
reception. Missing aggregation evidence prevents resolving whether those
differences reflect critic/community preferences, a small sample, or another
basis. Independent providers' counts must not be attached to ScreenScraper data.
Do not add title-specific boosts, pretend null counts are sufficient, average
unlike measures, or accept all scores merely because authentication succeeded.

## Method and scope

The opt-in `public reception assessment capture through persistent worker` in
`test/screenscraper_live_smoke_test.dart` requested twenty unique public official
games across PS1, PS2, GBA and GameCube. It used the normal persistent refresh
worker and request budget, not a parallel scraper. Each accepted identity came
from an offered, platform-checked candidate, explicitly reviewed before its
live game-information request. Results were read back from the ordinary cache.
The test asserts that capture cannot approve ranking eligibility.

The first search left six games without candidates. Separately requested
diagnostic aliases recovered those same games; aliases are not extra sample
members. Four used filename-style separators, Mario required `And` rather than
`&`, and Wind Waker required explicit review of the offered GameCube ID 4745
after article-position differences. No alias retry or article-reordering rule
was introduced into production. An exact offered title is fixture evidence,
not permission to silently accept arbitrary user-library search matches.

Retrieval dates below are UTC on 2026-10-03. All twenty IDs, scales and cached
results were verified live. No private collection, ROM payload, artwork download,
Drive file or Thor storage participated. Published comparison evidence was read
on the same date. The table separates aggregate critic, aggregate community and
individual-review evidence; these are not interchangeable.

## Public sample evidence

| Platform / game | ScreenScraper ID; raw → /100 | Retrieved UTC | Independent reception, platform-specific |
| --- | --- | --- | --- |
| PS1 / Final Fantasy VII | 19249; 18 → 90 | 13:23:42 | [Metacritic critics: 92/100, 20 reviews](https://www.metacritic.com/game/final-fantasy-vii/critic-reviews/) |
| PS1 / Metal Gear Solid | 19260; 19 → 95 | 13:23:05 | [Metacritic critics: 94/100, 20 reviews](https://www.metacritic.com/game/metal-gear-solid/?platform=playstation) |
| PS1 / Castlevania: Symphony of the Night | 19269; 19 → 95 | 13:25:39 | [Metacritic critics: 93/100, 12 reviews](https://www.metacritic.com/game/castlevania-symphony-of-the-night/critic-reviews/?platform=playstation) |
| PS1 / Croc: Legend of the Gobbos | 19412; 16 → 80 | 13:25:40 | [GameSpot: 5.8/10, one individual PS1 review](https://www.gamespot.com/reviews/croc-the-legend-of-gobbos-review/1900-2545938/); not a consensus aggregate |
| PS1 / Bubsy 3D | 19455; 10 → 50 | 13:23:20 | [GameSpot: 5.5/10, one individual PS1 review](https://www.gamespot.com/reviews/bubsy-3d-review/1900-2546891/); not a consensus aggregate |
| PS2 / Shadow of the Colossus | 21887; 18 → 90 | 13:22:54 | [Metacritic PS2 critics: 91/100, 77 reviews](https://www.metacritic.com/game/shadow-of-the-colossus/critic-reviews/?dist=neutral&platform=playstation-2); not the PS4 remaster |
| PS2 / Gran Turismo 4 | 21911; 18 → 90 | 13:23:29 | [Metacritic critics: 89/100, 74 reviews](https://www.metacritic.com/game/gran-turismo-4/) |
| PS2 / The Suffering | 22616; 17 → 85 | 13:22:56 | [Metacritic PS2 critics: 77/100, 47 reviews](https://www.metacritic.com/game/the-suffering/critic-reviews/?platform=playstation-2) |
| PS2 / Superman Returns | 22510; 10 → 50 | 13:22:53 | [Metacritic PS2 community: 3.2/10, 14 ratings](https://www.metacritic.com/game/superman-returns/user-reviews/?dist=negative&platform=playstation-2); small community sample, no accepted critic aggregate here |
| PS2 / God of War (2005) | 21899; 18 → 90 | 13:23:16 | [Metacritic critics: 94/100, 75 reviews](https://www.metacritic.com/game/god-of-war-2005/) |
| GBA / Advance Wars | 3782; 16 → 80 | 13:23:11 | [Metacritic critics: 92/100, 28 reviews](https://www.metacritic.com/game/advance-wars/) |
| GBA / Metroid Fusion | 3767; 16 → 80 | 13:23:25 | [Metacritic critics: 92/100, 44 reviews](https://www.metacritic.com/game/metroid-fusion/) |
| GBA / Mario & Luigi: Superstar Saga | 3762; 18 → 90 | 13:28:03 | [Metacritic critics: 90/100, 42 reviews](https://www.metacritic.com/game/mario-and-luigi-superstar-saga/) |
| GBA / Donkey Kong Country | 3831; 13 → 65 | 13:23:32 | [Metacritic GBA critics: 78/100, 26 reviews; community: 8.7/10, 181 ratings](https://www.metacritic.com/game/donkey-kong-country/); not a SNES score |
| GBA / Earthworm Jim | 3992; 14 → 70 | 13:23:08 | [Metacritic GBA critics: 72/100, 10 reviews](https://www.metacritic.com/game/earthworm-jim/critic-reviews/) |
| GC / The Legend of Zelda: The Wind Waker | 4745; 19 → 95 | 13:29:25 | [Metacritic critics: 96/100, 80 reviews](https://www.metacritic.com/game/the-legend-of-zelda-the-wind-waker/) |
| GC / Resident Evil 4 (2005) | 4750; 17 → 85 | 13:23:17 | [Metacritic GameCube critics: 96/100, 82 reviews](https://www.metacritic.com/game/resident-evil-4-2005/); not a later remake |
| GC / Eternal Darkness: Sanity's Requiem | 4777; 16 → 80 | 13:25:44 | [Metacritic critics: 92/100, 41 reviews](https://www.metacritic.com/game/eternal-darkness-sanitys-requiem/) |
| GC / Chibi-Robo! | 4856; 17 → 85 | 13:23:18 | [Metacritic critics: 75/100, 46 reviews; community: 8.7/10, 60 ratings](https://www.metacritic.com/game/chibi-robo/) |
| GC / Universal Studios Theme Parks Adventure | 5080; 9 → 45 | 13:25:41 | [Metacritic critics: 39/100, 11 reviews](https://www.metacritic.com/game/universal-studios-theme-parks-adventure/critic-reviews/) |

## Interpretation and unresolved acceptance

The 12-point differences for Advance Wars, Metroid Fusion and Eternal Darkness,
the 11-point difference for GameCube Resident Evil 4, and the GBA Donkey Kong
Country difference are material for ranking. Chibi-Robo's score is closer to its
community reception than its critic reception; this illustrates why the two
bases must be labelled rather than treated as interchangeable. Its ScreenScraper
score also ties Resident Evil 4 despite their different critic aggregates.
These observations do not prove a provider score is erroneous; they show why
an unexplained aggregate cannot yet substantiate the requested consensus Top.
Neither Croc's single review nor Superman's small community sample alone proves
a broad-consensus mismatch.

Those gaps belonged to the initial ScreenScraper pass. The legitimate IGDB
boundary now works; B4 was resolved before the following capture. This report
does not close S4 or authorize SD-card migration.

## IGDB remediation capture and decision

The opt-in `public IGDB reception assessment through persistent worker` used
real application authentication, platform/title discovery, explicit candidate
review, the normal serial refresh worker, SQLite publication and offline score
selection on 2026-10-03. It requested the twenty releases above, four Switch
releases and two separately identified projects. No ROM body, private library,
artwork or device storage was read. All 26 identities were matched; 24 returned
ratings and two honestly remained unrated. The first pass left Final Fantasy VII
ambiguous among three offered identities; a separate single-title diagnostic
explicitly reviewed original ID 427, not International or another same-named
entry. This benchmark-only choice does not modify production matching.

The [IGDB field contract](https://api-docs.igdb.com/#game) distinguishes the
average IGDB user rating and its count from external critics and their count.
Its total is based on both. Live returned totals in this sample equal the
mean of the two component averages when both exist, regardless of their counts.
That arithmetic is an observation of supplied values, not a new app formula.
Metal Gear Solid's total is 85.26 with a combined count of 1,713, yet its critic
component is one score of 80 and its community component is 90.52 from 1,712
ratings. Advance Wars similarly combines one critic score of 100 with 140 user
ratings of 84.12 to produce 92.06. A minimum combined count alone therefore
cannot prevent one critic from carrying half the result. **Do not approve the
blended total merely because its combined count is large.**

Select the externally defined game-level user average as the effective overall
game score, retaining `communityAggregate` / `IGDB users` provenance. It is not
a critic score, a popularity/download statistic or a claim of identical opinion
across sources. No highest-score selection, critic fallback, locally recomputed
average or per-title adjustment is introduced. Preserve the other fields for
inspection. Broader reception supports the qualitative high/middle/low ordering;
it does not prove identical fine-grained ranks or statistical certainty.

### Public cached sample

Values below are rounded for this report only; cached raw values/scales/counts
are unchanged. All retrievals were 17:44-17:45 UTC except Final Fantasy VII at
17:47:34 UTC on 2026-10-03. Independent older-release evidence is in the first
table; new comparisons and disagreements are resolved below.

| Platform / game | IGDB ID | Total / count | Users / count | Critics / count |
| --- | --- | --- | --- | --- |
| PS1 / Final Fantasy VII | 427 | 87.83 / 1634 | 90.66 / 1630 | 85 / 4 |
| PS1 / Metal Gear Solid | 375 | 85.26 / 1713 | 90.52 / 1712 | 80 / 1 |
| PS1 / Symphony of the Night | 1128 | 92.25 / 847 | 92.16 / 844 | 92.33 / 3 |
| PS1 / Croc | 7901 | 69.44 / 78 | 69.44 / 78 | missing |
| PS1 / Bubsy 3D | 7806 | 21.99 / 24 | 21.99 / 24 | missing |
| PS2 / Shadow of the Colossus | 2207 | 88.81 / 1344 | 89.13 / 1340 | 88.5 / 4 |
| PS2 / Gran Turismo 4 | 1601 | 86.08 / 174 | 85.50 / 171 | 86.67 / 3 |
| PS2 / The Suffering | 6180 | 79.08 / 94 | 76.66 / 90 | 81.5 / 4 |
| PS2 / Superman Returns | 6182 | 54.93 / 15 | 49.87 / 13 | 60 / 2 |
| PS2 / God of War (2005) | 549 | 88.42 / 1067 | 83.50 / 1064 | 93.33 / 3 |
| GBA / Advance Wars | 1691 | 92.06 / 141 | 84.12 / 140 | 100 / 1 |
| GBA / Metroid Fusion | 1104 | 84.73 / 314 | 84.47 / 312 | 85 / 2 |
| GBA / Mario & Luigi: Superstar Saga | 3351 | 85.71 / 200 | 85.42 / 199 | 86 / 1 |
| GBA / Donkey Kong Country | 150028 | 79.39 / 13 | 79.27 / 11 | 79.5 / 2 |
| GBA / Earthworm Jim | 362035 | missing | missing | missing |
| GC / The Wind Waker | 1033 | 88.61 / 1062 | 87.22 / 1061 | 90 / 1 |
| GC / Resident Evil 4 (2005) | 974 | 84.44 / 1696 | 87.28 / 1691 | 81.6 / 5 |
| GC / Eternal Darkness | 3907 | 86.09 / 96 | 82.17 / 95 | 90 / 1 |
| GC / Chibi-Robo! | 3856 | 79.82 / 39 | 79.63 / 38 | 80 / 1 |
| GC / Universal Studios Theme Parks Adventure | 4226 | 32.98 / 6 | 32.98 / 6 | missing |
| Switch / Breath of the Wild | 7346 | 95.04 / 3008 | 92.50 / 2981 | 97.59 / 27 |
| Switch / Super Mario Odyssey | 26758 | 92.77 / 1894 | 88.83 / 1877 | 96.71 / 17 |
| Switch / 1-2-Switch | 26762 | 51.67 / 42 | 49.68 / 33 | 53.67 / 9 |
| Switch / Balan Wonderworld | 135992 | 41.87 / 18 | 26.74 / 12 | 57 / 6 |
| SNES / Crimson Echoes (Hack) | 38266 | missing | missing | missing |
| GBA / Pokémon Unbound (Hack) | 141663 | 93.77 / 13 | 93.77 / 13 | missing |

### Independent evidence and disagreement resolution

- The community interpretation matters: [PS1 Metal Gear Solid users](https://www.metacritic.com/game/metal-gear-solid/user-reviews/?platform=playstation)
  rate it 9.2/10, agreeing with IGDB's 90.52 rather than its one-critic-dominated
  total. [Advance Wars](https://www.metacritic.com/game/advance-wars/) has
  community 8.6/10 from 189 ratings versus critics 92 from 28 reviews; IGDB
  users 84.12 fit the former. Neither site's votes are attached to the other.
- [Switch Breath of the Wild](https://www.metacritic.com/game/the-legend-of-zelda-breath-of-the-wild/)
  has critics 97/109 and community 8.9/27,036; IGDB users 92.50 remain in that
  acclaimed range. [Super Mario Odyssey](https://www.metacritic.com/game/super-mario-odyssey/critic-reviews/)
  is critically acclaimed at 97; IGDB users are lower at 88.83, explicitly not
  a reproduction of that critic score. [1-2-Switch](https://www.metacritic.com/game/1-2-switch/)
  is mixed at critics 58/63, consistent with IGDB's lower community 49.68.
- [Balan's Switch critics](https://www.metacritic.com/game/balan-wonderworld/critic-reviews/?platform=nintendo-switch)
  are 36/9, not the default PS5 page's 51. IGDB pools platforms and has only
  twelve user ratings; it cannot establish the Switch edition's exact reception
  or supported Top eligibility. That small sample is excluded, not boosted.
- The high-quality older titles' community averages need not equal critics:
  Resident Evil 4's 87.28 versus GameCube critics 96, Eternal Darkness's 82.17
  versus 92, and God of War's 83.50 versus 94 are comparisons of different
  populations, not proof of incorrect ROM identity. IGDB's reviewed global game
  ID may pool ports; never label it a platform-specific review average. The exact
  GBA port IDs for Donkey Kong Country/Earthworm Jim are distinct from the SNES
  originals, preventing borrowed base-release scores. Counts and source scope
  remain visible; this does not promise Metacritic's critic ordering.
- Croc and Bubsy's comparisons above are single professional reviews, not
  consensus aggregates. IGDB's community places Croc in the middle and Bubsy low;
  the single Bubsy 5.5 review cannot substantiate a broad-sentiment disagreement.
- [Crimson Echoes' independent playthrough review](https://retrocookie.com/2016/01/25/chrono-trigger-crimson-echoes-snes-rom-hack/)
  discusses its own strengths/weaknesses. Its real project match has no score;
  it stays unrated rather than inheriting Chrono Trigger's acclaim.
  [Unbound's author thread](https://www.pokecommunity.com/threads/pok%C3%A9mon-unbound-completed.382178/)
  establishes a separate FireRed hack and reports fan-favourite/gameplay awards,
  not a numeric consensus. Its 93.77 from thirteen votes stays advisory. Neither
  creator claims, awards nor an individual review manufactures missing votes.

### Accepted basis and limits

The fixed assessed precedence is IGDB's unaltered game-level community average
for PS1, PS2, GBA, GameCube and Switch. Require a current exact reviewed identity,
0-100 `communityAggregate`, known **at least 20 user ratings**, and the existing
original/project ownership checks. Twenty is an explicit conservative operational
floor above the small 6-15 vote captures, not a statistical confidence interval
or proof that twenty opinions represent everyone. No unknown-count exception or
critic/total fallback is approved. Nineteen sample games meet it; seven remain
unrated/unsupported. A two-vote extreme regression must not rank. SNES was tested
for project isolation, not given a platform-wide score approval from an unrated
project; other unassessed scopes remain advisory until evidence is recorded.

The selector must preserve the actual community score object for both display
and ranking. It must not relabel it `overallAggregate`, promote it merely because
an imported flag says approved, or silently substitute the total when its count
is inadequate. Whole-collection rankings remain visibly provisional while any
members are unrated, unresolved, low-support or outside the assessed scope. This
is a score-basis decision, not a curated Top list or permission for SD removal.
Production/query verification and the earlier unexplained host wait still belong
to S4 before stage closure; S5 owns the actual source/scope/coverage presentation.

## S7 mapped-scope extension — 2026-10-05

### Current Game Gear support boundary — 2026-10-06

A read-only public IGDB check used the existing application credentials, without
renewing its secret or changing the native database. `/v4/games/count` with
`where platforms = (35) & rating_count >= 20;` returned 19. The corresponding
bounded `/v4/games` query returned all 19 records, retaining original community
scores/counts and platform lists. This is an upper bound on supported candidates,
not nineteen accepted collection members: several records span other platforms,
and current identity/edition/release evidence remains required.

The query does not establish an adequate whole-collection ranking or authorize a
Game Gear basis extension. Do not lower the vote floor, import the provider's
global list as collection membership, borrow a different edition's score, or fill
25 positions with unqualified records. Complete the native fresh identifier pass
and subsequent current-bound IGDB pass; assess actual accepted evidence before
changing the production scope. Game Gear remains unapproved in the current
`productionOverallScoreBases`, and its uncertain ROMs remain protected from SD
removal. This is current S7 evidence, not a later-stage deferral or stage closure.

The subsequent normal Thor pass 75 reached a terminal result on 2026-10-07:
46 accepted matches, eight rated, 402 needs-review, 73 ambiguous and 25 unmatched
across 546 captured requests. A bounded read-only query joins only accepted job
75 items to current same-generation/same-identity IGDB records. All 46 agree;
eight contain valid 0-100 community scores, six with fewer than 20 votes and two
with at least 20 (two distinct provider records). This is substantially narrower
than the public 19-record upper bound. It does not supply defensible coverage of
the user's collection, resolve independent reception disagreements or approve
Game Gear Top membership. Preserve uncertain ROMs; do not turn eight displayed
scores into an invented ranked retention set. Full S7 acceptance remains open.

### Bounded alternative-source screening — 2026-10-07

This is S7 source-selection evidence, not a new approved ranking basis. RAWG's
[documented API](https://rawg.io/apidocs) supplies ratings/counts and offers a
key-required personal-use tier with attribution. A live read of its public
[Game Gear page](https://rawg.io/games/game-gear), parsing only the returned
initial-state game records, found 40 distinct records with at least 20 ratings;
all 40 span multiple platforms. That first page is neither full source coverage
nor accepted collection membership. Multi-platform aggregates are not inherently
invalid, but their counts alone do not establish edition ownership. The separate
[Sonic GG/SMS](https://rawg.io/games/sonic-the-hedgehog-ggsms) and
[Sonic 2 GG/SMS](https://rawg.io/games/sonic-the-hedgehog-2-ggsms) web-tool
representations each report only two ratings; these are not authenticated API
captures. Do not substitute the more popular parent records to repair
that support gap. No RAWG credentials, adapter or production policy were added.

The web-tool representation of GameFAQs [Game Gear Dynamite Headdy statistics](https://gamefaqs.gamespot.com/gamegear/586683-dynamite-headdy/stats),
labelled as crawled eight months earlier, identifies a 2.68/5 community average
from 34 users, separately from Genesis. This is not a fresh provider capture.
That is a potentially useful aggregate, not a reception assessment or binding to
the owner's collection. Direct host HTTP requests for a GameFAQs game-statistics
page and its robots document returned 403; some web-tool fetches also failed.
This does not prove permanent source unavailability. Supported access, permitted
automated use, broader coverage and exact identities remain unestablished; no
browser bypass, scraper or provider integration was introduced on this evidence.

### Extended reception capture — 2026-10-05

The existing opt-in persistent-worker capture was extended to fifteen public
official releases on N64, PSP and Game Gear. Each accepted fixture used one
literal offered title and the provider's platform-checked ID. It did not touch
the owner's device database or parallelize requests. A same-title pair of Game
Gear Sonic candidates remained unresolved. The PSP Dragonball fixture initially
had no literal candidate; a separate one-item capture used the actually offered
`Dragonball Evolution: The Game` title. No production alias rule was added.

Captured 2026-10-05 21:10:33–21:10:40 UTC; Dragonball recheck 21:11:39 UTC.
Below, scores are rounded to two decimals for documentation only. The normal
adapter/cache retained the returned raw value, 0–100 scale, kind and vote count.

| Platform / public release | IGDB ID | Community score / votes | Result |
| --- | ---: | ---: | --- |
| N64 / Super Mario 64 | 1074 | 88.66 / 2,082 | Exact original, not a hack or PC port |
| N64 / Ocarina of Time | 1029 | 91.53 / 2,176 | Exact original, not expansion/project candidates |
| N64 / Banjo-Kazooie | 2148 | 85.44 / 371 | Exact original, not hack candidates |
| N64 / Quest 64 | 3580 | 37.93 / 27 | Exact original |
| N64 / Superman: The New Superman Adventures | 3005 | 19.06 / 34 | Exact N64 game |
| PSP / God of War: Chains of Olympus | 552 | 77.35 / 326 | Exact reviewed game-level record |
| PSP / Lumines | 4689 | 80.91 / 29 | Exact original, not Lumines II |
| PSP / Metal Gear Solid: Peace Walker | 382 | 80.08 / 230 | Exact original, not Collector's Edition |
| PSP / The 3rd Birthday | 7359 | 69.74 / 24 | Exact original |
| PSP / Dragonball Evolution: The Game | 2571 | 27.77 / 10 | Too few votes; not ranking eligible |
| Game Gear / Shinobi | 10219 | 63.74 / 5 | Too few votes |
| Game Gear / Streets of Rage | 203317 | 79.77 / 5 | Game Gear port, too few votes |
| Game Gear / Sonic: Triple Trouble | 19556 | 79.38 / 19 | Too few votes |
| Game Gear / Super Columns | 19690 | Missing | Do not synthesize zero |
| Game Gear / Sonic the Hedgehog | Unresolved | Not captured | Two literal candidates, no automatic acceptance |

Independent reception checked the same releases, not similarly named remakes:

- [N64 Super Mario 64](https://www.metacritic.com/game/super-mario-64/) users
  9.0/10 (2,062 ratings), [Ocarina of Time (1998)](https://www.metacritic.com/game/the-legend-of-zelda-ocarina-of-time-1998/)
  users 9.1 (13,936), and [N64 Banjo-Kazooie](https://www.metacritic.com/game/banjo-kazooie/)
  users 9.0 (853) agree on high reception. The unsuffixed Ocarina page now
  describes an unrated Switch 2 release and was explicitly rejected.
- [GameSpot's original Quest 64 review](https://www.gamespot.com/reviews/quest-64-review/1900-2545042/)
  is 5.4/10, versus IGDB users 37.93/100: both are below the acclaimed examples,
  but an individual critic is not a community aggregate or exact numeric target.
  [GameSpot's Superman review](https://www.gamespot.com/reviews/superman-review/1900-2545277/)
  is 1.3/10 and explicitly discusses N64 gameplay, consistent with poor reception.
  Its incorrectly associated arcade game-hub footer was not used for identity.
- PSP [Chains of Olympus](https://www.metacritic.com/game/god-of-war-chains-of-olympus/)
  users 8.3/10 (1,583), [Lumines](https://www.metacritic.com/game/lumines/) 7.6 (60),
  [Peace Walker](https://www.metacritic.com/game/metal-gear-solid-peace-walker/?platform=psp)
  8.5 (811), and [The 3rd Birthday](https://www.metacritic.com/game/the-3rd-birthday/)
  6.3 (173) broadly agree on reception bands, not exact ordering. IGDB users
  put Lumines slightly above Peace Walker; no title boost or critic substitution
  is justified by a different community's ordering.
- [PSP Dragon Ball: Evolution](https://www.metacritic.com/game/dragon-ball-evolution/)
  users 1.7/10 (79) and critics 28/100 (16) support poor reception. The film's
  similarly named page was rejected. IGDB's ten votes remain advisory, despite
  agreement; independent counts cannot be attached to its record.

Decision: extend the already assessed IGDB game-level community basis to `n64`
and `psp`, without changing its scale, precedence, identity/ownership/freshness
rules, or known-at-least-20-votes requirement. Game Gear and other unassessed
scopes remain unapproved; this sample offers no supported Game Gear aggregate.
The same conservative floor excludes Dragonball's ten-vote score. This decision
does not approve every title, assert platform-specific averages, establish a
whole-collection Top, or authorize removal. Native integration of the extended
basis remains ordinary S7 work until verified on the current APK.

Verification: the focused support-boundary fixture failed before the scope
extension at the required twenty-vote case and passed afterwards. Effective-score
and indexed Library-query checks passed, including stale/unknown-count/project
ownership behavior. A fresh normal-worker public capture at 21:15:28–21:15:34 UTC
returned the same scores/counts; after its network adapter was closed, production
query selected exactly nine supported canonical games from fifteen fixtures,
with Top 25 also returning nine and coverage explicitly provisional. It did not
rank the sparse Game Gear records, unrated record, ambiguous Sonic or ten-vote
Dragonball. Scoped analysis and diff checks passed. No full suite, Gradle build
or native APK replacement was performed for this extension.

### GB/GBC reception coverage — 2026-10-07

The same opt-in public persistent-worker benchmark captured ten original GB/GBC
releases at 04:05:00–04:05:05 UTC using the legitimate existing IGDB credentials.
Literal offered titles and platform-checked candidate IDs supplied explicit
benchmark review, not a production title-only classification rule. Randomizers,
sequels and colour-conversion projects were not selected as the original game.
No private library, device job, ROM body or artwork participated. The fixture's
legacy catalogue schema was corrected to include populated non-null filenames,
matching the real schema after the initial local failure; production matching
was unchanged. The live capture and offline production query passed.

| Platform / release | IGDB ID | Community / votes | Support |
| --- | ---: | ---: | --- |
| GB / Super Mario Land 2: 6 Golden Coins | 1071 | 80.63 / 210 | Supported |
| GB / Link's Awakening (original monochrome) | 1028 | 86.42 / 235 | Supported; not DX or the Switch remake |
| GB / Metroid II: Return of Samus | 1102 | 73.12 / 92 | Supported; not Samus Returns |
| GB / Kirby's Dream Land | 1063 | 77.85 / 190 | Supported; not Dream Land 2 |
| GB / Batman Forever | 77350 | 70 / 2 | Too few votes |
| GBC / Pokémon Crystal Version | 1514 | 89.06 / 432 | Supported |
| GBC / Oracle of Ages | 1041 | 84.25 / 173 | Supported; not its randomizer |
| GBC / Wario Land 3 | 1698 | 79.89 / 58 | Supported; not The Master Quest or a colour conversion |
| GBC / Perfect Dark | 1464 | 62.13 / 9 | Too few votes; not the N64 record |
| GBC / The Grinch | 265046 | Missing | Unrated, not zero |

The [IGDB field contract](https://api-docs.igdb.com/#game) still supplies the same
user-average/count semantics. Independent Nintendo Life community records,
checked on 2026-10-07, distinguish these original platforms:
[Mario Land 2](https://www.nintendolife.com/reviews/2011/09/super_mario_land_2_6_golden_coins_3dsvc)
8.2/10 from 1,318 users;
[Link's Awakening](https://www.nintendolife.com/games/gameboy/legend_of_zelda_links_awakening)
8.9 from 720;
[Metroid II](https://www.nintendolife.com/games/gameboy/metroid_ii_return_of_samus)
7.1 from 794; and
[Kirby's Dream Land](https://www.nintendolife.com/games/gameboy/kirbys_dream_land)
7.6 from 646 agree on the GB reception bands and relative ordering.
[Crystal](https://www.nintendolife.com/games/gbc/pokemon_crystal) is 8.4 from 648,
[Oracle of Ages](https://www.nintendolife.com/games/gbc/legend_of_zelda_oracle_of_ages)
8.1 from 376, and [Wario Land 3](https://www.nintendolife.com/games/gbc/wario_land_3)
7.6 from 233: the two communities share that ordering but not identical values.
These independent counts never replace IGDB's own counts.

[GB Batman Forever](https://www.nintendolife.com/games/gameboy/batman_forever)
is 5.4/10 from 38 users, substantially below IGDB's two-vote 70/100. This is
exactly the sparse-sample risk addressed by the existing floor: exclude it from
Top claims, rather than boost, blend or invent votes. GBC
[Perfect Dark](https://www.nintendolife.com/games/gbc/perfect_dark) is 6.4 from
39 users, consistent with IGDB's 62.13 but still not sufficient to rescue its
nine-vote record. The Grinch remains unrated. Numerical agreement is not a vote
count or permission to borrow another port's stronger aggregate.

Decision: extend the existing game-level IGDB community basis to `gb` and `gbc`,
with unchanged scale, fixed precedence, exact ownership/platform/identity,
freshness and known-at-least-20-user-votes rules. The representative assessment
from S4 remains the foundation; this bounded extension checks new collection
scope, not a new estimator or a claim of complete collection coverage. No
ScreenScraper advisory promotion, critic/total fallback, hack-parent inheritance,
unknown-count exception, threshold reduction or removal authority is introduced.
Verification: the focused support-boundary regression failed before extension
and passed afterwards. Effective-score and production indexed-query checks
passed, retaining the low/unknown-vote, stale-record and ownership exclusions.
A fresh real-provider capture at 04:12:31–04:12:35 UTC returned the same evidence;
after closing its network adapter, the offline production query selected seven
supported canonical games from ten fixtures, with identical Top-25 membership
and explicitly provisional coverage. Scoped analysis passed. The normal updated
debug APK was subsequently built and installed without changing the saved
ScreenScraper capture. This public assessment is not a claim that the private
GB/GBC collection now has a complete defensible ranking.
