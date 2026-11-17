# Scorpion enemy verification (#855)

## Native demo

`native-demo.mp4` is20seconds of actual Godot4.5.1 running the production
EnemyScorpion, its normal behavior resource, the real Player with shipped
wizard art, and the real SpellCaster/WaterShot. It is a scratch flat-sand
fixture, not the overworld or an interactive browser session.

- Wake/rush: underground sand trail,0.30s emergence, locked sting tell/dash,
  dodge and forward-tip miss stun.
- Fighting: face player, repeated pincer tell/strike, actual player HP loss;
  later sting while player i-frames are enabled, followed by miss stun.
- Retreat: player moves beyond650px, scorpion follows then buries after
  two seconds out of range; remains hidden without healing.
- Last segment deliberately respawns an enemy, holds the forward strike
  pose and pauses its AI to isolate hit geometry. Three actual WaterShot
  casts: shell deals2 (12x0.2 truncated), tip-only casts each deal12.

Player positions/dodges are scripted; player locomotion is disabled. A
camera centers the enemy for visibility. No autoheal, HP floor, enemy damage
call substitution, changed spell stats or hidden production tuning. Last
segment's held pose is a named demo-only tweak, not evidence of the natural
0.5s duration. Core harness verifies that duration and freeze/thaw behavior.
Native frame captures and samples from the encoded MP4 were inspected.
The scratch recorder stays outside the repository.

## Mechanics

Godot4.5.1 full suite:63/63PASS on production-code head3d6319fb01f3066403313ee5eadec62af3025825.
Extended existing enemy-definition harness covers buried damage/targeting
refusal, normal state transitions, single shell reduction, direct raw
unlocated damage, pre-roll tip/AoE bypass, held miss pose through damage and
freeze/thaw, a real physics tip-only projectile hit and i-frame miss.
The existing weight registry now includes the new definition and scene.

A separate scratch actual Main/AreaLoader check mounted four scorpions via
the existing overworld spawner, verified every sample is sand and180px
outside the camera-sized barrier, and checked explicit player/terrain
wiring. Run retention/no respawn uses the existing retained-overworld,
first-mount-only spawner path. This was a source + native mount check, not
an interactive travel qualification.

## Boundaries

- No new lighting or audio changes. Existing ordinary-enemy harnesses pass.
- AoE applies full damage when the existing area's body-center candidate
  test lands a hit. This is the isolated all-AoE shell bypass policy.
- Raw/unlocated damage stays armored. No new DoT system is added.
- Pincer art impact is520ms from start (100ms first pose +420ms held pose),
  not420ms total. Sting tell is360ms.
- Initial underground rush and sting dash each have a200px maximum budget.
- Armor uses the existing float/truncation contract.80% shell reduction can
  yield19 for100base due to binary float representation, not a new rounding
  rule; the implementation does not round the intermediate value.
- Native test/demo only. Browser play, obstacle-rich chase/dash and external
  displacement qualification remain unverified; no claim of those checks.

## Review correction: rendered-pose geometry

The revised tip projection reads the actual animation direction suffix and
frame, never player aim. Transition projection includes the source rig's
base gait sway, added tail sway, lateral shake, vertical drop and occlusion.
Sand-only frames have no exposed tip. The actual shipped frame pixel gates
sand-covered/invisible projected tips; results cache once per pose. Sprite
frame/animation changes synchronize the collider as well as physics/render
updates. No art changed.

`pose-proof.png` is native Godot rendering of emerge/bury SE and walk NW,
all with aim fixed RIGHT. Red circles show the actual12px weak-spot geometry;
there is no circle on sand-only poses. The scratch driver sets individual
frames for inspection; it is not an interactive terrain navigation demo.
The existing core harness checks all272source poses across seven actions
and eight directions against expected coordinates independently captured
from the committed Python pixel rig, plus actual-frame occlusion gates.
Revised production source full suite63/63PASS; native demo rerecorded after
the geometry correction. Browser/obstacle-rich play remains unverified.
