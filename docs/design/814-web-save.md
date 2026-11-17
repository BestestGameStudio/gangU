# Browser run persistence

Requested: local browser saves so refresh/close does not restart the run.

Existing settings/Bestiary saves are separate; ProgressionCarry only spans in-process death reloads.

Web-only persistence, versioned local snapshot with safe validation. Preserve existing death rules: progression survives, wallet/world reset. Area checkpoint reconstruction versus exact live enemy/projectile restoration is being scoped before implementation. No native-desktop behavior changes, no terrain changes.
