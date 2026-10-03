# Live overall-score assessment — 2026-10-03

Authority: SPECIFICATION.md, META-05. Owner: S4; current stage state and remaining
host-evidence blocker are in IMPLEMENTATION_STATUS.md and
S4_ACCEPTANCE_RECONCILIATION.md. Source assessment is not whole-stage closure.

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
