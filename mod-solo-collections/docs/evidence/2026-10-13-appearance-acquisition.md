# Appearance acquisition — 2026-10-13

## Item receipts

The C++/SC2 collection service now records acquired canonical armor/weapon
appearances without requiring equip, soulbinding, character usability or expiry
of refund/trade flags. It verifies the live server item owner before enqueueing
the stable appearance identity. Unknown catalogue sources and non-appearance
items still cannot grant an unlock. The normal account transaction/revision
queue remains the only writer; duplicate events do not create duplicate unlocks.

Loot/master loot, crafting, vendor rewards, quest-granted items and new inventory
stores retain their existing receipt hooks. Login and five-second reconciliation
scan equipment, carried bags and the bank. Pre-save scans and outgoing inventory
transfer events additionally catch existing-item paths on older supported Cores.
On those Cores, a received mail/trade/auction item may first appear at the next
reconciliation or save because it does not emit `OnPlayerStoreNewItem`.

Acquisition changes no item binding/refund flags and performs no transmog apply.
Normal class/weapon/slot application rules, equipment-instance binding and paid
application remain in place. No protocol, schema or catalogue identity changes.

## Quest rewards

`OnPlayerCompleteQuest` forwards successful turn-ins to `OnQuestRewarded`.
The production helper requires the server's `IsQuestRewarded` state, then visits
all positive-count fixed and choice reward source IDs. Empty slots, zero counts,
duplicate IDs, missing templates and sources absent from the canonical appearance
catalogue are ignored. Character usability and the chosen reward index do not
limit collection; additional physical items, toys or spells are not granted.

The hook timing was checked against the supported local AzerothCore headers and
`Player::RewardQuest`, which marks rewarded history before invoking the hook.
See the [upstream reward implementation](https://github.com/azerothcore/azerothcore-wotlk/blob/master/src/server/game/Entities/Player/PlayerQuest.cpp).
`IsQuestRewarded` is used rather than `GetQuestRewardStatus`, whose repeatable-quest
semantics differ. Login visits `getRewardedQuests()` to backfill older fixed/choice
appearances through the same queue with `HistoricalReconcile` (no new badges).

## Verification

The portable acquisition test executes the same ownership/source helper used by
the production service: unequipped/unbound/refundable/tradeable equipment, weapons,
foreign owners, missing templates, non-equipment, null/disconnected players.
Core hook contracts additionally cover inventory reconciliation and registration.
Quest behavior tests execute the same production helper: unrewarded quests do not
enqueue anything, all fixed/choice rewards are visited, repeats/empty/zero-count
slots are skipped, rewarded history works for reconciliation, and null/offline
players are rejected. The full portable gate passes 45 contracts plus three
native executables, built with warnings treated as errors.
Full AzerothCore integration build and live acquisition/relogin remain pending.

Live acceptance: loot unequippable armor and an unbound BoE without wearing them;
craft/buy an item; take mail/trade/auction gear; check carried and banked items on
login; confirm unlocks survive relog and appear on an account alt. Different
accounts must remain isolated. Applying a collected look must retain its normal
server-calculated fee.

Quest acceptance: complete objectives without turning in (no unlock), turn in a
quest with multiple armor/weapon choices (all appearances unlock, one physical
choice), turn in a repeatable quest, relog a character with old rewarded history,
and verify duplicate/repeat turn-ins do not advance ownership twice. Non-equipment
rewards and unknown/missing catalogue entries must never grant arbitrary IDs.

## Deployment

Rebuild/install the module with the existing matched catalogue. The current AddOn
already consumes type 13/20 unlock deltas; no AddOn/protocol change is required.
No live server, database or client has been modified by this source work.
