# 0015. Fast-forward merges without squash

Status: Accepted, 2026-11-18. Supersedes the merge method in [ADR 0009](0009-trunk-based-git-workflow.md).

## Context

GitLab creates squash commits with the merging user's GitLab commit email, so the commit on `main` loses the author's own identity. The small Conventional Commits on a branch are also useful history that a squash throws away.

## Decision

Merge requests use fast-forward merges without squash. Branches are rebased onto `main` before merging, and each commit keeps its author. The rest of ADR 0009 stays: protected `main`, short-lived branches, Conventional Commits and a green pipeline.

## Consequences

History on `main` stays linear and is the branch's commits as written, so each commit must be meaningful; fixup commits are squashed locally before merging. A merge request must be rebased whenever `main` has moved.
