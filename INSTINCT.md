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
- Keep changes small and disjoint: one concern per PR beats a mixed bundle. A side fix
  discovered during other work gets its own issue and PR.
- Split big features into multiple issues and discuss the architecture with the other
  Instincts before implementing. Bring the owners only the questions that survive that
  discussion.
- If you have no assigned work, actively look for a free approved issue and claim it in
  its thread rather than idling - no two sides own the same work at once.

## 2. Suggestions need human approval

- Gameplay or design ideas that an Instinct originates are filed as issues tagged
  `suggestion`. The tag is only for Instinct-originated ideas, never for owner requests.
- No Instinct starts work on a `suggestion` issue without explicit approval from a human
  owner. Bugs can be logged and worked on without approval.

## 3. Commit early, label honestly

- Commit and push early and often. Small incremental commits over one large drop.
- Open a PR as a **draft** as soon as you start work, even if it is empty - every
  in-progress task has a PR. Mark blocked or dependent work explicitly (e.g.
  `[DRAFT, depends on B]`). Never mark a PR ready while it is known-failing or
  unverified.
- Verify each push against the actual remote branch before reporting it done.

## 4. Every PR states exact scope and evidence

- **Scope:** the exact files changed and the behavior change intended. If the scope grows
  after review has started (new files, a moved head), say so explicitly - approvals do
  not carry over silently.
- **Linked issue:** the body names the issue it resolves with `Closes #N` so the issue
  closes automatically on merge.
- **Evidence:** automated test results on the exact head, and for gameplay-visible
  changes, a working demo video of the running game attached to the PR. Screenshots may
  supplement the video but never replace it. Author-captured evidence supports the PR;
  it never substitutes for the reviewer's own check.

## 5. Independent review on the exact head

- Every PR is reviewed by another Instinct, never its author. Reviewers are assigned
  automatically as individuals: no one manually requests, adds, or reallocates
  reviewers, and only the individually assigned reviewer acts on the request. After
  the author pushes fixes, they may re-request review on the same PR from that same
  assigned reviewer; if the automatic assignment changes, the current assignment
  stands and no one restores a previous reviewer by hand. One exception: when the
  author pushes a conflict-resolution head, no automatic assignment fires on the
  push, so the author may manually re-request review on the same PR from another
  Instinct (Daniel, 2026-11-08: "fix the conflicts and re-request review from
  another instinct") - never from themselves. Prioritize incoming review
  requests over new implementation - a review can run in parallel with your own work.
- Review against the exact current head commit and name its SHA in the review. An
  approval applies to that head only - new pushes reset it and require a fresh review.
- When an Instinct starts a review, it adds a comment to the PR saying the review
  is underway, so the author and other reviewers can see it is being looked at.
- Review checks: the diff matches the stated file boundary, CI is green on that head,
  tests pass, and gameplay claims are verified against the rendered build where
  applicable.
- If the only findings are process issues (e.g. the PR description), the reviewer fixes
  them directly instead of bouncing the PR back to the author.
- If a PR is blocked by conflicts with the base branch, the author fixes the conflicts,
  pushes the new head, and re-requests review from another Instinct (the manual
  re-request exception above - the author must not review their own resolution).
  Approvals and findings on the pre-conflict head do not carry over.

## 6. Merge after approval, exactly once

- A PR merges once it has an independent approval on its current head and a green CI run
  on that head. Approved PRs merge promptly - they do not sit idle.
- Exactly one merge executor per PR, agreed explicitly between the sides (in the PR
  thread or in coordination between the Instincts) before merging. Before executing,
  re-confirm the PR is still open - a human owner may have merged it - and that the
  approval and CI still cover the current head.
- No direct pushes to `main`, and no merging on your own approval - the qualifying
  approval always comes from a reviewer other than the author.
- After merging, confirm the linked issue closed automatically. If the closing link is
  missing or wrong, fix the PR body link (`Closes #N`) through the normal route rather
  than closing issues by hand.

## 7. Merged is not live is not playable

Every push to `main` rebuilds and republishes the web build to GitHub Pages. Track
status precisely:

- **Merged** - the commit is on `main`.
- **Live** - the Pages deploy for that commit succeeded and the site serves it.
- **Playable** - the change has been verified in the actual browser build.

A shipped gameplay change is not done until it is live and playable. Deployment and
playable verification are not tied to one side - the author and reviewers coordinate who
runs the check. Docs and other non-gameplay changes are done when merged with their
content verified against the relevant sources - no browser check applies. Report status
with the right word.

## 8. Keep the repo public-safe

- This repo and everything committed to it is public. Working agreements, architecture
  decisions (see ARCHITECTURE.md), and design docs belong here.
- Private correspondence, credentials, personal configuration, and anything not meant
  for public view never get committed.

## 9. Diagnose and repair repeated CI failures

- When CI repeatedly fails on the same step with the same observed error, diagnose and
  repair it rather than parking the work. File an issue naming the failing run, step
  and observed error; distinguish evidence from an unknown root cause.
- Use the normal PR route: a minimal repair, green CI on the exact head, and independent
  review before merge. Never weaken checks, skip steps, merge around red CI, or loop
  unchanged re-runs. Bounded attempts with backoff and captured diagnostics can improve
  resilience without proving the underlying cause is fixed.

## 10. Stay usefully occupied within agreed scope

- Prioritize incoming reviews, then claim useful approved work per section 1: a free
  issue, qualified backlog research, or an agreed repair. Coordinate claims and file
  ownership before starting so there is only one writer per scope.
- Preserve owner permissions and design gates: suggestions still need human approval,
  and unresolved owner design decisions are not permission to invent gameplay.
- Move the project forward without busywork, churn commits, or work outside agreed scope.

## 11. Tests run in CI, not locally

- Instincts do not create, edit, or run tests locally. The test suite runs in CI; the
  CI results on the exact head are the test evidence a PR cites (section 4).
- The one-line `test407` relax merged in #547 was a one-off owner-approved exception,
  not a precedent.
