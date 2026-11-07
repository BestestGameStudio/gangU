# INSTINCT.md - Contributor Working Agreements

gangU is built by its collaborators' Instinct assistants (`instinct-projects`, `instinct-dc`,
`instinctmitra`), each acting under its owner's direction. This file records the working
agreements every contributor follows on this repository. It covers public project workflow
only.

## 1. Coordinate through issues and file ownership

- Work is broken down in GitHub issues. Claim an issue, or a defined scope within one,
  before starting.
- Before editing, check open issues and PRs for overlap. State the files you intend to
  touch in the issue or PR description, and treat them as exclusively yours until that
  PR closes. Do not edit files covered by someone else's open PR without coordinating in
  the issue thread first.
- Keep changes small and disjoint: one concern per PR beats a mixed bundle.

## 2. Commit early, label honestly

- Commit and push early and often. Small incremental commits over one large drop.
- Open a PR as a **draft** until it is genuinely ready for review. Mark blocked or
  dependent work explicitly (e.g. `[DRAFT, depends on B]`). Never mark a PR ready while
  it is known-failing or unverified.

## 3. Every PR states exact scope and evidence

- **Scope:** the exact files changed and the behavior change intended. If the scope grows
  after review has started (new files, a moved head), say so explicitly - approvals do
  not carry over silently.
- **Evidence:** automated test results on the exact head, and for gameplay-visible
  changes, screenshots or recordings of the running game. Author-captured evidence
  supports the PR; it never substitutes for the reviewer's own check.

## 4. Independent review on the exact head

- Every PR is reviewed by someone other than its author. An author never approves their
  own PR.
- Review against the exact current head commit and name its SHA in the review. An
  approval applies to that head only - new pushes reset it and require a fresh review.
- Review checks: the diff matches the stated file boundary, CI is green on that head,
  tests pass, and gameplay claims are verified against the rendered build where
  applicable.

## 5. One merge executor

- Merges to `main` are performed by the designated merge executor (currently
  `instinct-projects`), only after an independent approval on the current head and a
  green CI run on that head.
- No one approves their own work: the required approval always comes from a reviewer
  other than the author. When the merge executor authored the PR, the same rule
  applies - it merges only after another contributor's independent approval on the
  current head.

## 6. Merged is not live is not playable

Every push to `main` rebuilds and republishes the web build to GitHub Pages. Track
status precisely:

- **Merged** - the commit is on `main`.
- **Live** - the Pages deploy for that commit succeeded and the site serves it.
- **Playable** - the change has been verified in the actual browser build.

A shipped gameplay change is not done until it is live and playable. Docs and other
non-gameplay changes are done when merged with their content verified against the
relevant sources - no browser check applies. Report status with the right word.

## 7. Keep the repo public-safe

- This repo and everything committed to it is public. Working agreements, architecture
  decisions (see ARCHITECTURE.md), and design docs belong here.
- Private correspondence, credentials, personal configuration, and anything not meant
  for public view never get committed.
