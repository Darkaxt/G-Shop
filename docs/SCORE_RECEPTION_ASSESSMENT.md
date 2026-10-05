# Live overall-score assessment — 2026-10-03

Authority: SPECIFICATION.md, META-05. Initial assessment owner: S4 (closed).
The collection-scope extension below belongs to ACTIVE S7. Current stage state
is in IMPLEMENTATION_STATUS.md. Source assessment is not whole-stage closure.

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
