# Signature Rock lure recasts

Daniel confirmed alternate-only scope. tier3 placed anchor/lure alternate, not the direct primary group hook.

- Previous position: original lure cast location, independent of enemy/player motion.
- Four automatic recasts after the original catch: five successful catches total.
- Counter belongs to each pair; anchor stays fixed and both endpoints share the budget.
- Only successful arrival recasts. Timeout, enemy death, jump detach and replacement remove the pair.
- Return travels at spell projectile speed; no capture while returning.
- No additional mana/cooldown payment for automatic returns.

Implementation uses a successful-arrival signal, per-pair counter and non-capturing flying return. Full58/58 and actual-main scripted lifecycle clip recorded.
