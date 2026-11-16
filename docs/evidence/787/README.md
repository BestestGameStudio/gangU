# Rock fishing (#787)

Signature retains the Mastery primary cast. Ctrl+fire places a fixed anchor at the player's cast location and lure at the mouse's cast location, without following either afterward. Three pairs per player; a fourth replaces the oldest. Pairs last until owner death/scene exit or replacement.1s cast cooldown, no invented ongoing cost.

Lure taunt pulse immediately and every5s, chosen radius180px. Nearby enemies move toward the lure under a temporary taunt locomotion override (safe for Player-typed boss behaviors); touching within16px acquires an anchor-targeted reel. Same force/weight/cap and1.5s arrival stun. Taunt is cleared on acquisition. A pair lost during reeling releases control. World/terrain/boundary collision still applies.

One Fishy whistle emitter per player while any pair exists, at5s or cue-length intervals, whichever is longer. Visual notes/actual art arrive in PR790; this stage has temporary geometry.

Mastery upgrade quest is the requested placeholder5casts. Test787 covers alternate payload, three-pair oldest replacement, fixed snapshots despite player movement, immediate/five-second taunt, touch-to-anchor reel and quest5casts.

Daniel follow-up: catching one enemy consumes a pair. Its lure follows that enemy during reeling and disappears with the pair when the enemy arrives at the anchor; the anchor then disappears too. Interrupted/dead/owner-lost reels also clean up the consumed pair rather than leaving a dangling anchor. Uncaught pairs still persist until replacement/owner exit.
