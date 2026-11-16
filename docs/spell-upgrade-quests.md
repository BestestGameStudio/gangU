# Per-spell upgrade quests

Each SpellUpgrade may define a SpellUpgradeQuest resource. It replaces only that row's cast threshold. Rows with no quest keep cast-count qualification. Shop acquisition and existing one-tier boss-token bypass are unchanged.

Kinds: casts, redirected projectile hits, short-window volley. Data owns objective, goal, volley size and window. SpellProgress observes casts and accepted projectile-hit receipts from the player's caster. Only the held current source tier advances. Refused hits, zero HP loss, non-enemy targets and other attackers do not count.

Water Shot:
- Base to Hover: five redirected projectile hits. Same enemy allowed across shots; one shot/enemy pair counts once. Successful redirect/release/re-aim marks the shot.
- Hover to Reservoir: three distinct projectiles damage one enemy within0.15seconds. Repeat ticks from one shot cannot substitute for distinct shots. Late hits start a new window.
- Reservoir to Tide: placeholder quest, cast five times.

Concealed cards show objective, progress bar/count, but not upgrade effect copy until applied. Totals follow current progression carry including death/area travel. A fresh application session starts at zero; no new disk-save system. Transient shot dedup/windows are not carried because projectiles do not survive scene reload.

HitEvent adds immutable projectile identity/redirect facts. Optional OnHit.report arguments preserve existing callers. Redirect/release alone never credits a damage quest.
