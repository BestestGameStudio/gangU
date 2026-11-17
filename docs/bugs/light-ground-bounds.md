# Ground canvas light bounds investigation

Read-only isolation found GateHub and Desert arena PointLight2D rendering cost dominates their script/particle work on the software renderer. Offscreen-only culling changes no pixels but saves no meaningful cost. Excluding ground from light changes many pixels and is rejected.

Prototype: split the giant world-coordinate painted-ground quad into256px canvas items sharing its material. Same shader/world positions/art, tighter light bounds. Initial paused same-boot gate and arena pixel comparisons are exact; frame-wall medians190.7->168.9ms and355.0->323.8ms. Needs repeat camera/zoom/time tests before implementation acceptance. Software llvmpipe only, no user-GPU speed claim.

## Broader validation: not safe to ship

Actual prototype code passed60/60 native tests. Six same-boot paused camera/zoom comparisons: arrival, arena, field, zoom0.8 and fractional zoom1.1 were exactly equal. South beach at zoom1.25 changed46,686 pixels even with Engine.time_scale0, with small scattered ground-colour changes. The likely cause is varying interpolation precision across a changed triangulation, but that attribution is not proven. Hard pixel-identity requirement fails, so implementation was not pushed and no render code is in this PR. The prototype also adds840 canvas nodes; unlit field/south medians were1.5-2.9ms slower in a single sample, another tradeoff needing work.

Offscreen-only light culling: exact pixels, no material benefit (gate189.1->189.1ms, arena359.4->356.7ms). Restricting lights away from ground is faster but changes46,321 gate/374,332 arena pixels; rejected as a visual change. Source already disables arena light shadows. Reducing texture/range/scale changes the lit output, so no such change was built.

No proven pixel-identical fix is ready. Draft stays investigation-only. Frame-wall timing is llvmpipe software rendering, not GPU/user performance. Future map-colour work #835 must remain untouched; any resumed source work rebases after it lands.
