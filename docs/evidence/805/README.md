# General reel force and Sand General

Sand General weight4 (between Warlord3 and Beast5). Generated encounter definitions now set this explicitly.

This is not a flat charge multiplier. Enemy behaviors continue choosing self-propulsion while held, but terrain_move_and_slide submits it instead of moving a second time. Arena-owned movement uses Enemy.submit_external_motion. The reel's sole movement pass combines propulsion with integrated external force:

F_i = target_direction * hook_reel_acceleration * displacement_force
v_pull_next = clamp_length(v_pull + sum(F_i)/max(weight,0.1)*dt, pull_speed_limit)
v_net = clamp_length(v_self + v_pull_next,2400)

Single pull limit retains min(2400,1500*displacement_force/weight). Shared groups use the heaviest living member for acceleration and speed. Stacked pulls sum force vectors and their speed budgets before the2400 resultant cap. Ordinary no-propulsion stop paths remain unchanged. Player stop32px; anchor18px. Force is integrated once per enemy, not once per contributor movement. Current force_step constant2400 is the shared reel resultant cap.

The Sand arena submits each tick's planned displacement, not an absolute-position overwrite. Existing displacement persists instead of being undone next frame. Charge contact tests use the actual actor position, not the unresisted planned path.

Assumption: "jumping removes the anchors" means the Sand General going airborne, not the player jumping. Its jump detaches attached Rock anchor/lure pairs and their pull contributions only; other regular reels survive. Player death, reel timeout and other contributor cleanup remain independent.

Own scripted tests cover no force, opposing/stacked/perpendicular forces, weight1 versus4, an ordinary charger using the common propulsion capture, generated boss mass, arena displacement persistence, jump pair cleanup and remaining regular ownership. Existing stop/stack suites remain part of the full run.

charge-forces.mp4 is an actual-game scripted Sand General shield-charge recording:0 opposing reels travels175px,1 travels123px,2 travel71px over the same sampled charge. Real arena attack/reel/enemy code runs; the script selects the attack and manually advances equal time windows. It is not an interactive browser playthrough. Visuals inspected at576x324. Jump cleanup is currently a scripted physics assertion rather than demonstrated in this clip.
