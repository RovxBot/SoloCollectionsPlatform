# Mount shortcuts and gameplay boundary — 2026-10-23

The matching changes live in `mod-solo-collections` and the sibling
`SoloCollections` AddOn. Merge/package them together. Rebuild and deploy the
module first, then install the matching AddOn. SC2, SQL and catalog hashes are
unchanged.

## Behavior

- Both mount journal views drag reusable macros containing stable collection
  IDs. Characters need not learn shared mount spells. Repeated drags reuse the
  same macro; account slots are preferred, with character slots as a fallback.
  Full macro lists and combat block dragging without replacing player macros.
- Every shortcut calls the existing server-authorized SC2 summon action.
  Ownership, lifecycle, action eligibility, race/class, actual riding skill and
  spell location checks remain on the server.
- Summons use `TRIGGERED_NONE`. AzerothCore treats even the previous limited
  triggered flags as a triggered cast, which skips its movement checks.
- Removed automatic riding training, mount-spell learning, speed changes,
  flight overrides and native mount reconciliation on each player update.
- The optional random-mount DBC builder preserves every existing spell record,
  including flying-area restriction attributes.
- The production config now contains 26 settings in 54 lines. Omitted legacy
  options retain their previous defaults and remain optional without emitting
  missing-key warnings.

## Observed checks

- Source/static: `git diff --check` passed. Every public config setting has a
  source reader; no duplicate keys.
- AddOn: all Lua files passed syntax checks with Lua 5.4. The active journal/
  wardrobe runner passed: 135 tests ran, with 5 existing deferred-feature skips.
  Its new behavioral harness covers account sharing, macro reuse across
  AddOn reloads, stale ownership, combat, capacity, and the DragonUI adapter.
  Synthetic DBC records verify preservation of every existing spell field.
- Portable build: 52 module contracts passed; C++20 domain, SC2 protocol and
  appearance acquisition executables built and passed with warnings as errors.
- Broader module contracts: 140 ran; 7 failures were reproduced unchanged on
  the original HEAD. They concern legacy logging/shadow contracts, companion
  action text, preview logging and startup build logging.
- Full Core/module integration build: pending. A syntax attempt using local
  Core headers stopped at missing `boost/version.hpp`.
- Server runtime, real-client interactions and visual acceptance: pending.
  Portable tests do not establish those outcomes or Lua 5.1 runtime acceptance.

## Remaining deployment acceptance

1. On two characters of one account, collect a mount on only one character.
   Drag it from both supported journals on the other character, place it on a
   bar, summon, reload, relog and repeat. Repeated drags must reuse its macro.
2. Attempt mounting while moving; start moving during the normal cast. Both
   must follow Core's rejection/interruption rules. A stationary summon must
   retain its normal cast time. Check individual and random shortcuts.
3. With insufficient riding skill, login, level and attempt shared summons.
   Riding skill/spells must remain unchanged. Repeat with legitimately trained
   riding and verify native speed, zone and Cold Weather Flying requirements.
4. Verify ordinary battleground mounting, indoor restrictions, mount switching,
   native class mounts and no extra flight in Azeroth.
5. Confirm full macro lists and combat show errors without altering existing
   macros, and that shortcut use still rejects missing server ownership.

Older versions may already have persisted riding skills and mount spells.
These changes do not revoke them because their provenance cannot safely be
distinguished from legitimate training. Any repair requires administrator review.
If an older client overlay cleared native mount flight attributes, rebuild it
from an unmodified baseline; updating this source alone does not repair an
installed overlay. No live database, client data or server runtime was modified.
