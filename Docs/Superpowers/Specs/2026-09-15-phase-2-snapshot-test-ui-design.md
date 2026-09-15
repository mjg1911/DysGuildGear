# Phase 2 Snapshot Test UI — Design

**Status:** Approved design

**Date:** 15 September 2026

**Purpose:** Define the minimum in-game interface for verifying the Phase 1 local gear snapshot.

## Scope

Phase 2 adds a small read-only window opened through a slash command. It lets the player visually inspect the complete local snapshot saved by Phase 1.

## Display

The window shows the recorded character name and realm, the snapshot capture time, record completeness, and all tracked equipment slots. Each populated slot shows the saved item link; an empty equipped slot is displayed explicitly. If no valid complete record exists, the window displays a clear **No saved snapshot** state.

## Boundaries

The window only displays the local player's saved record. It does not write or refresh data, inspect another character, open automatically at login, or send or receive addon messages. As a result, opening and using it produces no guild traffic or gameplay automation.

## Validation

After logging out and back in, opening the window must show the same character identity, capture timestamp, completeness state, and saved slot values present in `GuildGearMemoryDB`. Testing must also cover a missing-record state and an empty equipment slot.
