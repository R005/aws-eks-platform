# 0009. Trunk-based Git workflow

Status: Accepted; merge method superseded by [0015](0015-fast-forward-merges-without-squash.md), 2026-10-25

## Context

We want a linear history in which every commit on `main` is reviewed, passes CI and is deployable, with commit messages tools can parse.

## Decision

`main` is protected: changes land only through a merge request with a green pipeline. Branches are short-lived, named `<type>/<short-description>`, and rebased on `main` before merging. Commits follow Conventional Commits, enforced by a `commit-msg` hook. Merge requests are squashed and merged fast-forward only. GitLab project settings are kept in code where possible.

## Consequences

History is linear, with one commit per change, easy to bisect and revert, and messages can drive changelogs. A branch must be rebased whenever `main` moves. Branch-level commits are lost on squash; the merge request keeps the discussion.
