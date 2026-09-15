# Guild Gear Memory — Development Phases

**Status:** Working project roadmap  
**Date:** 15 September 2026  
**Purpose:** Break Guild Gear Memory into manageable development phases so the project can be built, tested, and validated step by step without trying to complete the entire addon at once.

---

## 1. Why the project is split into phases

Guild Gear Memory combines several different responsibilities:

- learning and remembering gear;
- deciding which gear changes are meaningful;
- sharing confirmed changes with other addon users;
- detecting missed updates;
- repairing incomplete records;
- preventing unnecessary guild traffic;
- presenting the stored information clearly to the user.

Trying to build all of these systems at the same time would make it difficult to know where a problem comes from. A bug in local gear tracking could look like a synchronization problem, while a network problem could look like a bad cache.

The project should therefore be developed in phases. Each phase adds one major capability and should leave the addon in a state that can be tested before the next layer is added.

The phases are designed around the agreed Guild Gear Memory product model:

> Capture a complete gear state once, hold new slot changes locally until they prove stable, share only confirmed changes, and repair gaps only when somebody actually needs the data.

---

# Phase 1 — Local Gear Memory

## Goal

Create the basic local gear-memory system without any addon-to-addon communication.

At this stage, Guild Gear Memory should understand the player's equipped gear and be able to preserve that information locally.

## What this phase should provide

The addon should be able to:

- recognize the player's equipped items;
- create a complete gear snapshot;
- associate that snapshot with the correct character;
- remember the snapshot between reloads and game sessions;
- load previously stored gear information when the addon starts;
- distinguish between a complete usable record and missing data.

The stored data becomes the foundation for every later phase.

## What this phase does not include

This phase does not include:

- pending gear changes;
- the five-minute stability rule;
- communication with other addon users;
- guild-wide gear sharing;
- sequence numbers;
- incomplete-record repair;
- responder selection;
- polished guild-facing UI.

## Phase completion target

Phase 1 is complete when the addon can reliably answer:

> **What gear did this character last have when Guild Gear Memory recorded a complete snapshot?**

The information must survive a reload or relog.

---

# Phase 2 — Basic Snapshot Test UI

## Goal

Create a deliberately small, read-only in-game window for checking the local gear snapshot created in Phase 1.

This UI exists so the saved data can be tested visually in the game before the project adds pending-change tracking or guild synchronization.

## What this phase should provide

The addon should provide a window that the player opens with a slash command. The window should display:

- the recorded character name and realm;
- when the snapshot was captured;
- whether the record is complete or unavailable;
- every tracked equipment slot and its saved item link, or an explicit empty-slot value.

The window must show a clear **No saved snapshot** state when Phase 1 has not yet recorded usable gear data.

## Testing scope

The UI is a testing tool, not the final browsing experience. It should be intentionally basic:

- local-player data only;
- read-only;
- no manual capture or refresh control;
- no inspection of other characters;
- no addon-to-addon communication;
- no automatic opening at login.

The player opens it when needed with the documented slash command, views the saved result, and closes it normally.

## Why this phase comes next

Phase 1 now has verified SavedVariables output. A small display window makes it easier to validate the same data in the game, including empty slots, item links, character identity, and reload/relog persistence.

It also provides a safe visual test surface without changing data or producing network traffic.

## Phase completion target

Phase 2 is complete when the player can open the test window and reliably answer:

> **What complete gear snapshot does Guild Gear Memory currently have saved for this character?**

The displayed information must match the snapshot persisted by Phase 1 across a reload or relog.

---

# Phase 3 — Stable Gear Change Detection

## Goal

Teach the addon the difference between a temporary gear swap and a meaningful long-term gear change.

This phase introduces the local pending-change system and the configurable stability period.

The default stability period for the MVP is five minutes.

## Main concept

For synchronization purposes, each equipment slot has three important states:

### Shared

The last confirmed item that is considered the character's stable known gear.

### Current

The item the character is wearing right now.

### Pending

A current item that differs from the last shared item and is waiting to see whether it remains equipped long enough to become meaningful.

## Expected behavior

If a player changes an item:

1. The new item becomes pending.
2. Nothing is shared yet.
3. The addon waits for the configured stability period.
4. If the item is still equipped when that period finishes, the change becomes confirmed.
5. If the player returns to the previously shared item before the period finishes, the pending change disappears.
6. If the player changes the slot to another new item, the stability period restarts for that slot.

Each slot behaves independently.

For example, changing a ring must not reset the pending timer for a weapon.

## Why this phase matters

Players frequently change gear temporarily for testing, comparisons, role changes, equipment sets, or other short-lived reasons.

Guild Gear Memory should not create guild network traffic for every temporary equipment event.

By solving this locally first, later synchronization phases only need to distribute gear changes that have already been confirmed as meaningful.

## What this phase does not include

This phase still does not communicate with other addon users.

Confirmed changes exist only inside the local addon for now.

## Phase completion target

Phase 3 is complete when the addon can reliably answer:

> **Has this equipment change remained stable long enough to become part of the character's shared gear state?**

Temporary or reverted swaps must produce no confirmed change.

---

# Phase 4 — Basic Addon-to-Addon Synchronization

## Goal

Allow participating Guild Gear Memory users to exchange confirmed gear information.

This is the first phase where the addon begins behaving as a distributed guild gear cache rather than only a local memory system.

## Expected behavior

When a local gear change becomes confirmed, other participating addon users should be able to learn that change.

Normal synchronization should update only the slots that actually changed.

For example:

```text
Bob previously shared:
Head = Helmet A

Bob keeps Helmet B equipped long enough for it to become confirmed.

Other addon users learn:
Bob
Head = Helmet B
```

They do not need Bob's entire equipment set again if they already possess a complete baseline.

## Complete snapshots

This phase also introduces the ability to exchange a complete snapshot when one is genuinely required.

A complete snapshot is useful when:

- another addon user has never learned the character before;
- the receiving addon does not have a usable baseline;
- a direct complete copy is specifically requested.

Complete snapshots are not the normal steady-state synchronization method.

## First usable distributed behavior

By the end of this phase:

- one addon user can hold a character's complete gear record;
- stable confirmed changes can update that record on another addon user's client;
- the receiving user can keep the learned gear after the original character goes offline.

This establishes the basic distributed-cache concept.

## What this phase does not solve yet

This phase does not yet need to solve every guild-scale problem.

In particular, the later phases will handle:

- missed update detection;
- incomplete records;
- repair selection;
- many users responding to the same request;
- large-guild traffic control.

## Phase completion target

Phase 4 is complete when two participating addon users can keep a complete gear record synchronized through confirmed slot changes without repeatedly exchanging full equipment snapshots.

---

# Phase 5 — Missed Updates and Record Repair

## Goal

Make the distributed cache aware of situations where synchronization is no longer trustworthy.

Addon messages can be missed. Players can disconnect. Channels can be unavailable. A receiving addon may simply not have been online when an update happened.

Guild Gear Memory must recognize this instead of pretending its cached data is complete and current.

## Confirmed change sequence

Confirmed shared changes have a lightweight sequence or version.

The sequence exists to identify whether the receiver missed one or more confirmed changes.

Example:

```text
Local record:
Bob sequence 184

Next received update:
Bob sequence 185
```

The record can continue normally.

But if the next received update is:

```text
Bob sequence 187
```

then the addon knows that confirmed changes were missed.

## Incomplete records

When the addon knows that confirmed updates are missing, the character record becomes:

> **Incomplete / refresh needed**

The addon must not silently claim that the record is synchronized.

It may still display the information it has, but the user should be able to see that the record is no longer fully trustworthy.

## Repair behavior

Repair should happen when the missing or incomplete gear is actually needed.

For example, when the user opens Bob's gear:

- if Bob is available and a valid current snapshot can be obtained, use that;
- otherwise, request a complete cached copy from participating guild members;
- if no suitable complete copy exists, keep the record incomplete or show no data.

The important rule is that becoming incomplete does not create a permanent polling loop.

## Phase completion target

Phase 5 is complete when the addon can answer:

> **Do I know that this cached record is complete, and if not, can I repair it when the user actually needs it?**

At this point the core Guild Gear Memory MVP behavior is present.

---

# Phase 6 — Guild-Scale Networking and Anti-Storm Protection

## Goal

Make the synchronization system safe and practical when many guild members are running Guild Gear Memory at the same time.

A design that works between two players can still behave badly in a 20-, 30-, or 40-player group.

This phase focuses on keeping network behavior bounded and conservative.

## The duplicate-cache problem

Because Guild Gear Memory is distributed, several online players may possess the same complete cached record.

Example:

```text
Alice has Bob sequence 194
John has Bob sequence 192
Sarah has Bob sequence 194
Mike has Bob sequence 190
```

If another player asks for Bob's gear, the addon should not cause all four users to send Bob's entire snapshot simultaneously.

Only the necessary useful response should ultimately be transferred.

## Responder selection

This phase introduces a method for deciding which available user should provide a requested cached snapshot.

The exact networking strategy may evolve during implementation, but the product behavior should satisfy these principles:

- prefer the best complete copy;
- avoid many identical full responses;
- stop unnecessary responses once a suitable source has been selected;
- do not keep retrying without a limit;
- do not turn one request into guild-wide message spam.

## Traffic control

This phase should also establish the project's wider communication limits.

Guild Gear Memory must avoid:

- recurring guild-wide polling;
- periodic database synchronization;
- full-database broadcasts;
- unlimited retries;
- repeated requests for the same character while one is already being handled;
- large bursts caused by many nearby guild members;
- unnecessary responses from multiple users who all hold the same cached data.

Time passing by itself must never create guild network traffic.

## Raid and large-group behavior

The addon must remain well-behaved when many guild members are nearby or in the same raid.

Being near 20–40 guild members must not cause the addon to repeatedly inspect everyone or generate a large burst of synchronization traffic merely because those characters became visible.

The addon should continue using the same principle as the rest of the design:

> Do work because useful gear information is needed, not merely because another player happens to be present.

## Phase completion target

Phase 6 is complete when Guild Gear Memory can operate with many participating guild members without creating response storms, unnecessary full snapshots, recurring polling, or uncontrolled retries.

---

# Phase 7 — User Experience, Freshness States, and Release Hardening

## Goal

Turn the working synchronization system into a clear and dependable addon that guild members can actually use.

The earlier phases focus mainly on whether the data is correct and whether synchronization behaves properly.

This phase focuses on making that state understandable to the user and validating the addon as a whole.

## Guild gear browsing

The user should be able to view the gear records Guild Gear Memory knows about.

The interface should make it clear whose gear is being viewed and what level of confidence exists in that data.

## Freshness states

The product design defines several important states.

### Current / synchronized

A complete gear record exists and the addon does not know of any missed confirmed update.

### Recently observed

A complete snapshot was obtained recently through direct observation or inspection, but continuous synchronization is not guaranteed.

### Cached

A complete saved snapshot exists, often for an offline or unavailable character, but the character may have changed gear since that snapshot was learned.

### Incomplete / refresh needed

The addon knows that one or more confirmed updates were missed.

The record may still contain useful information, but it must not be presented as fully synchronized.

### No data

No complete usable gear record is available.

## Configuration

The user-facing settings should include the stability delay.

The recommended default remains five minutes, while other sensible choices may be offered.

Changing the duration does not change the product rule:

> A gear change is shared only after it remains equipped for the selected stability period.

## Release validation

Before the addon is treated as ready for normal guild use, the full behavior should be tested across situations such as:

- UI reloads;
- logging out and back in;
- temporary gear swaps;
- stable gear changes;
- multiple slot changes;
- large gear-set swaps;
- missed synchronization messages;
- offline characters;
- duplicate cached copies;
- incomplete-record repair;
- many participating guild members;
- addon-message throttling or failure;
- unavailable gear information;
- mixed or outdated addon versions where applicable.

## Policy review

The completed behavior must remain inside the project's addon-policy guardrails.

Guild Gear Memory must continue to:

- use only Blizzard-supported in-game addon mechanisms;
- avoid external memory or packet access;
- avoid automation of gameplay;
- respect protected, secret, or unavailable information;
- avoid excessive addon communication;
- avoid misleading the user about cached or incomplete information.

## Phase completion target

Phase 7 is complete when Guild Gear Memory is understandable to normal users, behaves correctly under expected failure conditions, stays within the project's policy rules, and is suitable for real guild testing and release preparation.

---

# Overall Development Milestones

The phases can also be grouped into three larger milestones.

## Prototype — Phases 1 to 4

At the end of Phase 4, Guild Gear Memory should demonstrate the complete core idea:

- remember gear;
- display the saved local snapshot for testing;
- filter temporary changes;
- share confirmed changes between addon users.

This proves that the product concept works.

## Core MVP — Phases 1 to 5

At the end of Phase 5, the addon also understands when its data is incomplete and can repair records when necessary.

This is the minimum point where the distributed cache behaves as a resilient system rather than only a basic synchronization demo.

## Guild-ready MVP — Phases 1 to 7

At the end of Phase 7, the addon includes:

- reliable local memory;
- a basic local snapshot test UI;
- stable-change detection;
- incremental synchronization;
- complete snapshots where required;
- missed-update detection;
- on-demand repair;
- guild-scale anti-storm protection;
- clear freshness states;
- user-facing browsing and configuration;
- release and policy validation.

This is the point where Guild Gear Memory should be ready for wider real-world guild testing.

---

# Phase Summary

| Phase | Main purpose | End result |
|---|---|---|
| **1 — Local Gear Memory** | Learn and persist gear locally | The addon reliably remembers a complete gear snapshot |
| **2 — Basic Snapshot Test UI** | Visually check the saved local snapshot | The player can inspect the Phase 1 snapshot in a read-only testing window |
| **3 — Stable Gear Change Detection** | Filter temporary gear swaps | Only meaningful long-term changes become confirmed |
| **4 — Basic Synchronization** | Share gear between addon users | Confirmed slot changes update distributed cached records |
| **5 — Missed Updates & Repair** | Detect unreliable cached state | Incomplete records are identified and repaired on demand |
| **6 — Guild-Scale Networking** | Prevent excessive traffic and response storms | The system remains efficient with many addon users |
| **7 — UX & Hardening** | Make the addon understandable and release-ready | Users can trust what the addon displays and the system is ready for guild testing |

---

# Final Project Rule

Every phase should preserve the same product philosophy:

> **Learn complete gear when legitimately available, remember it locally, ignore temporary equipment changes, share only stable confirmed changes, detect when information is incomplete, repair it only when needed, and keep guild communication as small and infrequent as practical.**
