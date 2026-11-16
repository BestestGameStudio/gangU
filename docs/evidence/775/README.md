# Rebinding script UID repair

PR776 adds the two omitted committed files: game/ui/key_bindings.gd.uid and tests/ui/test767_key_rebinding.gd.uid. The actual git-tracked audit now passes and the full local suite passes44/44. No gameplay change.

The CI-masking repair is NOT included. Existing hosted CI can still fall back to a filesystem scan after import, masking missing tracked UIDs. Workflow git access plus a fail-closed audit require workflow-scope access; the current credential's push was rejected. This remains open separately in issue777. No enforced CI audit is claimed by PR776.
