# 0001. Record architecture decisions

Status: Accepted, 2026-10-25

## Context

The platform involves many choices whose reasons are easy to forget, and people will ask why something was done a certain way.

## Decision

Each significant decision is an ADR in `docs/adr/`, one file per decision named `NNNN-kebab-title.md`, with Context, Decision and Consequences. ADRs change through merge requests. An accepted ADR is not reversed; a new ADR supersedes it.

## Consequences

The reasoning is versioned next to the code and reviewed with it, unlike a wiki. Each significant change carries a little extra writing.
