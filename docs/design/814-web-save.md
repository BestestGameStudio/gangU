# Browser progression persistence

Daniel clarified: "No just save the progression elements not actual real time fights etc".

Web export only. Each load starts at the hub with fresh HP and actors. Save these progression elements in same-origin browser localStorage:
- Unlocked spells, inventory and hotkey slot layout.
- Cast and quest progress, upgrade tiers/tokens, owned relics.
- Coins, carried consumables/revive items, fixed revive-item claim.
- Canonical cleared rooms and Sand General completion.
- Explored map and user marks.
- Shop stock and paid-refresh count, reward-pool eligibility.

No position, HP, shields, projectiles, summons, active anchor pairs, enemy or boss state machines, pending ground drops or day/night clock. Reloading while loot is still on the floor does not collect it. There is no new fight checkpoint or rollback system.

Death keeps the established rule: spells/upgrades/relics survive; money, carried run items, shop, world and map reset. A synchronous death save runs before the death pause so closing the tab cannot restore the previous money. No extra new-run button is introduced; death remains the existing new-run route.

Saves happen every second, after key progression changes, and synchronously on beforeunload/pagehide/hidden visibilitychange. localStorage avoids waiting for an asynchronous IndexedDB flush at tab exit. Close/crash/mobile process termination can still miss the last second if lifecycle callbacks are not delivered. Storage blocked/full shows an in-game warning. Clearing browser site data removes the save. This is per browser profile/origin, not account/cloud sync; concurrent tabs use last writer wins.

Schema version1,4MB limit, SHA256 corruption check, resource whitelist (only data .tres with expected classes), no Object deserialization. Bad/unsupported saves safely start fresh with a warning. Compatible versions stay under a stable key; future incompatible versions must migrate explicitly rather than silently interpreting old data.
