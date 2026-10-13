# Wardrobe polish validation — 2026-10-13

## Scope and product rules

Transmog remains equipment-instance-bound. The server still charges its existing
per-changed-slot fee. There is no automatic outfit activation, gear-upgrade replay,
free outfit switching or automatic retry of paid writes. Saved outfits remain
manual presets, and only C++/SC2 can authorize and apply appearances.

## Source checks

Run `python3 tools/collections/check_wardrobe.py` from the SoloCollections root.
The active addon, bridge, SC2 and camera contracts plus behavioral harnesses pass:
132 checks, five explicit deferred-toy skips. Every canonical addon Lua file parses.
This environment uses Lua/luac 5.4; the tool prefers 5.1 when available. The changed
runtime code uses Lua 5.1 syntax/APIs. Real 3.3.5a runtime remains unobserved here.

The retired inline wardrobe renderer checks and old M2 pose-cache/direct-display
checks have been removed from the active gate. Item cards now use the EzWardrobe
Transmorpher pipeline. Their replacement executes that renderer with controlled
native frames: separate ClearModel/SetUnit frames, bounded viewports, actor reuse,
late cache callbacks, generation rejection, hidden cleanup, idle-driver cleanup,
unknown-race rejection and missing weapon-preview capability.

The other behavioral harnesses exercise quote invalidation, refreshed paid
confirmation, slow replies without retries, duplicate replies, same-template item
swaps, localized search, alternate item IDs, isolated preferences, reversible set
tracking, authoritative partial-set drafts and manual saved-look previews.

These are source/portable results, not server, game-client or visual acceptance.
The broader historical catalogue/release suites are outside this focused gate.

The module's `python tools/check_portable.py` also passes: 31 wardrobe/security
contracts and both portable domain/protocol executables built with C++20 and
warnings treated as errors. Obsolete comment-text assertions were replaced by
checks for the actual failure/guard branches; the protocol test's temporary-string
loop now uses an explicit value. No server billing or gameplay implementation changed.

## Required real-client acceptance

| Case | Expected result |
| --- | --- |
| Select an appearance and immediately change it | Previous price disappears; Apply waits for the new quote |
| Confirm after a price or equipment change | Review/reconfirmation required; no stale-price apply |
| Receive a write acknowledgment after five seconds | Waiting feedback, then one success; no repeated paid request |
| Receive no acknowledgment for 60 seconds | Result described as unconfirmed; no automatic retry |
| Equip a second copy of the same item | Old applied badge/tooltip does not transfer to the new item |
| Upgrade equipment | New item retains its own appearance; applying a look uses normal gold costs |
| Cold-cache enUS search and item-ID search | Readable loading label; native English name becomes searchable when cached |
| Close/reopen journal and studio | Page, selection, searches and filters retained; each window has independent filters |
| Favorite an appearance and enable Favorites Only | Starred matches plus the studio's pinned current/hide actions |
| Track/untrack a set | Tracked-only view updates; missing-piece tooltip lists progress |
| Click a missing set piece | Item browser opens on that source; Alt-click retains alternative-source cycling |
| Use collected pieces of an incomplete set | Only owned appearances on occupied slots enter a draft; paid confirmation remains required |
| Save/load/update/delete an outfit | Thumbnail refreshes; hidden slots retained; loading performs no apply |
| Open Outfits and switch back to Items/Sets | Eight set-preview frames reused; no ghost models or extra renderer pools |
| Change account character or use two accounts | Shared account state reconciles; separate accounts remain isolated |

Check stock small/large races and both sexes, hunter ranged gear, oversized
weapons, robes and shields; test supported configurations with/without SoloCam.
Use 1280×720, 1920×1080 and 2560×1440 with multiple UI scales. Verify the third
studio tab, reduced progress bar, Save/Update button and Track Set button do not
overlap, truncate or escape the window. Camera tuning requires before/after
real-client screenshots under the camera contribution guide.

## Deployment

These changes use the existing protocol and server billing; there are no schema,
catalog identity or generated mapping changes. Use the canonical addon under
`addon/SoloCollections`. Suite copies must be generated through suite tooling,
with provenance/lock updates if a suite is rebuilt. No live client/server was
modified, and no release was published.

Full catalogue/source localization still needs reviewed locale inputs. Detailed
source enrichment, cross-installation appearance/set favorites, recent-use views,
outfit action-bar shortcuts and weapon illusions remain independent later work.
