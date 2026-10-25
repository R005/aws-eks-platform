# 0009. Trunk-based Git workflow

- **Status:** Accepted
- **Date:** 2026-10-25

## Context
We want a linear, readable history in which every commit on `main` is reviewed, passes CI and is deployable, plus commit messages that tools can parse (changelogs, semantic versioning).

## Decision
- **Protected `main`:** no direct pushes and no force pushes. Changes land only through a merge request with a green pipeline.
- **Short-lived branches** off `main`, named `<type>/<short-description>` (for example `feat/api-healthcheck`, `docs/project-readme`). Each one lives hours to a few days and is rebased on `main` before merging.
- **Conventional Commits:** `<type>(<optional scope>): <description>`, with types `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `ci`, `build`, `perf`, `style`, `revert`. A `commit-msg` hook (`conventional-pre-commit`) enforces it locally.
- **Merge method:** squash the commits and merge with **fast-forward only**, so each MR becomes exactly one Conventional Commit on `main`, with no merge commits.
- The GitLab project settings that enforce this (protected branch, merge method, squash, "pipelines must succeed") are kept in code where possible (for example the `gitlab` Terraform provider).

## Consequences
- History is linear: one commit per change, easy to bisect and revert.
- Commit messages can drive changelogs and versioning.
- Fast-forward-only means a branch must be rebased whenever `main` moves.
- Branch-level commit detail is lost on squash. The MR keeps the discussion.

## Alternatives considered
- **GitFlow (develop/release/hotfix branches):** heavyweight for a single deployable trunk with continuous delivery.
- **Merge commits:** keep branch history, but clutter `main` and make it non-linear.
- **Rebase without squash:** linear, but work-in-progress commits end up on `main`.
