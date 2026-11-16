# Enemy weight (#779)

`EnemyDefinition.weight` is an exported float. `Enemy.weight` copies it on definition assignment, like the existing stats. It is a relative, unitless value, not kilograms: ordinary mustache warrior = 1.0. No clamping or gameplay consumer was added.

| Existing definition(s) | Weight | Reason |
| --- | ---: | --- |
| Bird | 0.5 | Light flying animal |
| Fishy, overworld fishy | 0.75 | Lighter than human baseline |
| Wolf | 1.0 | Medium animal |
| Mustache warrior, red mustache, barricader, overworld guard/migrant/patrol | 1.0 | Human baseline, same across behavior variants |
| Slime, slime guard/patrol | 1.5 | Dense, broad-bodied enemy |
| Mustache warlord | 3.0 | Large human boss |
| Defense wave boss | 3.0 | Large boss |
| Head boss | 4.0 | Large floating boss |
| Beast boss | 5.0 | Heaviest existing boss |

These are editable defaults, not derived from HP or speed. All 17 production definitions explicitly serialize a weight.

Existing knockback already accepts fixed velocity pushes with 1800 px/s² deceleration and a 60 px/s control threshold. This change leaves that code untouched: no weight scaling, movement, damage, collision, AI or visual changes.

## Verification

Godot 4.5.1 headless suite: 46/46 pass. New `test779_enemy_weight` loads all 17 definitions, checks exact values and runtime copies, instantiates all 11 concrete enemy scenes, tests fractional assignment/resource isolation/replacement and verifies identical knockback push acceptance across all weights. No visual change, so no screenshot claim.
