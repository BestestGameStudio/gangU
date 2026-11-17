# Ground canvas light bounds investigation

Read-only isolation found GateHub and Desert arena PointLight2D rendering cost dominates their script/particle work on the software renderer. Offscreen-only culling changes no pixels but saves no meaningful cost. Excluding ground from light changes many pixels and is rejected.

Prototype: split the giant world-coordinate painted-ground quad into256px canvas items sharing its material. Same shader/world positions/art, tighter light bounds. Initial paused same-boot gate and arena pixel comparisons are exact; frame-wall medians190.7->168.9ms and355.0->323.8ms. Needs repeat camera/zoom/time tests before implementation acceptance. Software llvmpipe only, no user-GPU speed claim.
