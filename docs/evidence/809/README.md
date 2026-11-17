# Signature Rock alternate recasts

Daniel confirmed this applies only to alternate fire (Ctrl+fire). Primary Magnet group hook is unchanged.

Each fixed anchor/lure pair allows four automatic recasts after its original catch, for five successful catches total. Successful arrival releases the enemy, leaves the anchor fixed and flies only the lure to its original cast location at spell projectile speed. The pair cannot catch during this flight. Counters are independent per pair, not shared between casts. The fifth successful arrival removes both endpoints. A failed reel (timeout, death, invalid target), boss jump detachment, player death or cap replacement does not earn a recast. Automatic recasts do not spend more mana or restart the player's cast cooldown.

`lure-recasts.mp4` boots actual main.tscn in the hub and runs the production pair/reel code. The recording script positions a stationary enemy at the original lure point for each catch. Labels show the four automatic returns and fifth-catch removal. This is scripted gameplay, not an interactive browser playthrough. `return.png` shows the first return in progress. Inspected the clip/contact sheet and final still at768x432. Reproduce with `tools/showcase/record_lure_recasts.gd` and Godot Movie Maker at60fps.

Full local suite58/58 PASS. Dedicated test809 covers five catches, exact original location despite player movement, no capture mid-return, fixed anchor, independent budgets, release-before-return, timeout/death cleanup and cap replacement releasing ownership. Existing stop/stack/Sand jump suites also pass.
