# Browser progression persistence verification

Actual Godot4.5.1 web exports running WebGL in local Chrome, not native/headless engine substitutes. Chrome automation is headless-browser WebGL/SwiftShader, not a human playthrough, Safari or mobile-browser test. No live deployed save was read or changed.

1. `tests/browser/test_web_save.py`: temporary isolated fixture export with a test-only mutation/readback bridge. Validates refresh, actual beforeunload, hidden visibilitychange, tab close/reopen, quota error preserving last valid save, closing during death pause, corrupt/future-version rejection and blocked storage. Browser results are in browser-results.json. Fixture bridge is excluded from normal exports.
2. Normal RELEASE export, no test bridge: actual canvas click/Space input changes stored progression; refresh preserves the snapshot byte-for-byte; a complete Chrome context/browser close and relaunch with an isolated persistent profile also preserves it byte-for-byte. Console has no script/page errors. Restored screenshot shows normal game and non-overlapping restore notice.
3. Native full suite59/59PASS. test814 covers codec, exact resource identity/slots, duplicate relic data, shop subresources, wallet/items, tokens, cleared rooms, paid-refresh count, fixed revive claim, native disabled behavior and Sand completion without rewards/combat.

Warnings: Chrome software-WebGL GPU readback performance messages; not functional failures. Browser script uses temporary fixture state to test wallet/upgrades/death instead of playing hours to earn it. No mobile process-kill/OS crash guarantee; normal lifecycle callbacks can be skipped by a force kill, so the periodic save bounds ordinary unsignaled loss to roughly the latest second. Browser site-data clearing deletes progression. Same-origin, same-profile storage only; not cloud sync and concurrent tabs are last-writer-wins.

Reproduce fixture integration test:
`python tests/browser/test_web_save.py --godot /path/to/godot4.5.1 --chrome /path/to/chrome --output /tmp/web-save-evidence`
Requires matching Godot web export templates, Python playwright and Chrome. It copies the project to a temporary folder before fixture injection and never edits the working source or a normal browser profile.
