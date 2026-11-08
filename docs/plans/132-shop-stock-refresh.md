# #132 Shop stock refresh - settled spec + plan

Status: implementation on this branch, stacked on PR175 (`instinct-dc/156-shop-consumable`,
head f5f7ff6) because both touch `scripts/shop.gd` / `scripts/shop_panel.gd`. Merge order: 175, then this PR (retarget to main after 175 lands).

Settled spec (Daniel, WhatsApp, verbatim originals recovered):
- 2026-11-07 21:23:29 EST: "refresh stock when the player beats a dungeon, players can also buy a refresh. Each bought refresh costs extra. Example 1 > 2 > 3 > 5 > 8"
- 2026-11-07 21:23:57 EST: "yes refresh the paid price" (victory resets the paid price)
- 2026-11-08 00:19:40 EST: "show 4 slots for now, if theres no eligible item display an out of stock sign"
- 2026-11-08 00:20:17 EST: "fibonacci yeah" (continuation 1,2,3,5,8,13,21... confirmed)

Design:
- `Shop` keeps a stock of `stock_size` (4) slots drawn without replacement from `offerable_entries()` (non-owned rotation per the shop.gd ownership pin; consumables stay re-purchasable per #156).
- Free refresh on confirmed dungeon victory only (`Main._on_objective_completed` -> `Shop.on_dungeon_victory()`); victory also resets the paid counter to 0.
- Paid re-roll: `Shop.buy_paid_refresh()` charges `ShopRefreshSchedule.price_at(count)` (data-driven seeds 1, 2 -> Fibonacci continuation), then re-rolls. Refused with no charge when unaffordable or when no re-roll could surface a new good.
- Run-start reset comes free from the existing full-scene reload (wallet/satchel pattern).
- Panel renders exactly 4 slots; unfillable slots show an OUT OF STOCK sign; a RE-ROLL STOCK button shows the current price.
