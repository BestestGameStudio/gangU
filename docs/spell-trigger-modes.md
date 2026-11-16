# Spell trigger modes

`Spell.CastMode` is the effect shape (projectile, hammer, shield, etc.).
`Spell.TriggerMode` is the input contract. They are independent.

Spell resources declare `trigger_modes` as flags:

- `1`: DEFAULT. Press casts immediately, and hold repeats at cooldown.
- `2`: ALTERNATE. Alt+key selects the alternate for that press. Hold repeats
  at cooldown unless alternate charging is explicitly enabled.
- `4`: CHARGING. Hold starts charging after `charge_delay` (default 0.25s),
  release casts the charged effect. With DEFAULT also enabled, releasing
  before the delay casts default. A charge never also casts a default tap.

Examples:

- Ordinary spell: `trigger_modes = 1` (the default, no resource edits needed).
- Alternate + ordinary spell: `trigger_modes = 3`.
- Tap + hold: `trigger_modes = 5`, `charge_delay = 0.25`.
- All three: `trigger_modes = 7`; Alt chooses alternate only by default.
- Existing Vortex Hammer: `trigger_modes = 4`, `charge_delay = 0.0`. It still
  opens its vortex on press and swings on release, without a tap attack.

`alternate_spell` and `charged_spell` optionally point to effect resources.
Null reuses the source's effect. The source owns cooldown and cast/XP credit,
so changing mode cannot bypass cooldown. These references are effect payloads,
not recursive input routing. Payloads retain their own damage/cooldown values.

`alternate_can_charge` is opt-in. When true alongside CHARGING, holding Alt
uses the same delay. Its charged payload is `alternate_spell.charged_spell`
when present, otherwise the alternate payload itself. Without an alternate
payload it uses the source's charged payload. Alt is latched on key press,
so changing the modifier during a hold cannot switch payload halfway through.

`SpellTriggerRouter` is the shared, scene-independent input state machine.
The caster feeds all six slot actions and the generic cast action through it.
The caster owns cooldown and charge effect lifecycle, not each new spell.
Modal UI/death cancel pending input without firing. Replacing a slot cancels
its old pending input. A charge held through cooldown starts once ready.

Direct `cast()` / `cast_slot()` are unchanged programmatic casts, not key
simulation. Fixtures can call the router/consumer to test input semantics.
No existing spell gains alternate payloads or tap/charge behavior implicitly.
