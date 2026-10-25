# 0001. Record architecture decisions

- **Status:** Accepted
- **Date:** 2026-10-25

## Context
This platform involves many choices (state locking, secrets, identity, networking, CI) whose reasons are easy to forget. Reviewers, contributors and future maintainers will ask "why was it done this way?"

## Decision
We record each significant decision as an Architecture Decision Record (Michael Nygard style) in `docs/adr/`:

- one Markdown file per decision, numbered `NNNN-kebab-title.md`
- a short template: Status, Date, Context, Decision, Consequences, Alternatives considered
- an accepted ADR is never rewritten. When a decision changes, a new ADR supersedes it.
- ADRs change through merge requests, like code

## Consequences
- The reasons behind decisions stay versioned next to the code.
- Each significant change carries a small amount of extra writing.

## Alternatives considered
- **Wiki / Confluence pages:** these drift away from the code and aren't reviewed in merge requests.
- **Only commit messages and README:** these are hard to discover and don't capture the alternatives that were rejected.
