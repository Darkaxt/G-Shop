# Live overall-score assessment — 2026-10-03

Authority: SPECIFICATION.md, META-05. Owner: S4 (ACTIVE).

## Decision

ScreenScraper's current `note` is usable as a labelled, sourced advisory score,
but this assessment **does not approve it as the consensus basis for Top-N**.
No score policy was enabled and no production score or matching rule changed.

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

META-05 remains unresolved. This sample covers ordinary older-console releases,
not the required newer-console and independently identified modified-project
coverage. No base-game rating may be substituted for a hack/project rating.
Low-vote outlier handling and the legitimate aggregate-source comparison still
require live evidence. These remain S4 acceptance work, not S5 deferrals.

The existing IGDB adapter is the legitimate aggregate-source remediation path;
its live boundary is currently blocked by B4 (the configured Twitch client/secret
pair was rejected at OAuth with HTTP 403 / invalid client). Resolving that pair
and performing the real comparison is required before approving a ranking basis.
This report does not close S4, approve a Top list, or authorize SD-card migration.
