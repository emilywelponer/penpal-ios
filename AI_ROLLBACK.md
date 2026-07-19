# PenPal AI Rollback Guide

This document explains how to disable or remove the experimental AI foundation without automatically running destructive commands.

## Disable AI Without Deleting Code

AI features are controlled by the central feature flag in `PenPal/AIConfiguration.swift`.

Set:

```swift
static let isAIEnabled = false
static let useMockAI = true
```

With `isAIEnabled` set to `false`, PenPal should show no AI buttons, menus, sheets, placeholders, or changed navigation.

## Return To The Pre-AI Version

The current stable non-AI checkpoint is tagged:

```bash
pre-ai-baseline
```

To return the outer project to that exact checkpoint:

```bash
git switch main
git reset --hard pre-ai-baseline
```

The app source is an embedded Git repository at `PenPal/`. To return that source repo too:

```bash
cd PenPal
git switch main
git reset --hard pre-ai-baseline
```

Do not run `git reset --hard` unless you intentionally want to discard local changes after the baseline.

## Delete The AI Branch

After switching away from the AI branch, delete it from the outer project:

```bash
git switch main
git branch -D feature/ai-foundation
```

Delete the matching branch inside the embedded PenPal source repo:

```bash
cd PenPal
git switch main
git branch -D feature/ai-foundation
```

## Notes

- The baseline tag exists in both the outer project repo and the embedded `PenPal/` repo.
- AI code should remain isolated behind `AIConfiguration.isAIEnabled`.
- Real AI network calls should not be added until explicit consent, privacy review, and provider configuration are in place.
