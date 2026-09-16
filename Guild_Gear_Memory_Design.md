# Guild Gear Memory — Product & Synchronization Design

**Status:** Agreed working design  
**Date:** 14 September 2026  
**Purpose:** Describe how we want the addon to behave, without tying the design to a specific code structure or library.

## 1. Core idea

Guild Gear Memory should act as a **distributed last-known gear cache for the guild**.

The addon should not constantly ask the guild for gear and should not synchronize everyone's full database. Instead, it should work from four kinds of information:

1. A **complete gear snapshot** used as a baseline.
2. **Local pending slot changes** when a participating player equips something different.
3. **Small confirmed slot-level updates** only after a changed item has remained equipped for a defined stability period.
4. An **on-demand complete refresh** when a baseline is missing or when the addon knows some updates were missed.

The normal steady-state network message is conceptually:

> **Player X changed slot Y into item P.**

However, that message is sent only after the new item has remained equipped long enough to be considered a meaningful change.

The default stability period for MVP is **5 minutes**.

---

## 2. Design principles

### No polling

There must be no timer that repeatedly asks guild members:

- what gear they have;
- whether their version is newer;
- whether somebody has a character cached;
- whether a cached record is still current.

Time passing by itself must not create guild network traffic.

A local timer may be used to decide whether a pending equipment change has remained stable long enough to be shared. This is **not polling the guild** and does not send anything until a real equipment change is confirmed.

### Event-driven changes

When a participating player actually changes an equipped item, the addon records that change locally as **pending**.

If the player keeps the new item equipped for the full stability period, the addon confirms the change and sends a small slot update.

If the player changes back before the stability period ends, nothing is sent.

### Incremental updates by default

Once a complete gear snapshot exists, the addon should normally send only confirmed changed slots rather than sending the whole gear set again.

Example:

```text
Bob changes his helmet.

Local pending state:
Head -> Helmet B

Five minutes later, Helmet B is still equipped.

Confirmed update:
Bob
Slot: Head
New item: Helmet B
```

Receivers replace only Bob's Head slot in their cached record.

### Temporary gear swaps should create no network noise

If a player briefly changes an item and returns to the last shared item before the stability period ends, the pending change is cancelled.

Example:

```text
Shared weapon:
Sword of Blood

22:00
Sword of Blood -> Blade of Truth
Pending change starts.

22:03
Blade of Truth -> Sword of Blood
Pending change cancelled.

Result:
Nothing is sent to the guild.
```

### Full snapshots are repair tools

A complete snapshot is mainly needed when:

- the character has never been seen before;
- the local cache has no complete baseline;
- one or more confirmed incremental updates were missed;
- the user explicitly needs a current copy and a current source is available.

The addon should not send complete snapshots just because a player logged in or because some amount of time passed.

---

## 3. Character gear record

For every guild character the addon knows about, the logical record should contain:

- character identity;
- last shared/confirmed equipped items by slot;
- current local equipped items for the local player;
- pending slot changes for the local player;
- when each pending slot change started;
- time of the last known confirmed update;
- source/freshness information;
- a lightweight confirmed change sequence/version;
- whether the record is considered complete or incomplete.

Only the latest useful confirmed gear state is required for the initial addon. A full historical timeline is not necessary for MVP.

---

## 4. Three slot states for the local player

For synchronization purposes, each equipment slot can conceptually have three states:

### Shared

The last item that was successfully confirmed and shared with other addon users.

### Current

The item the player is wearing right now.

### Pending

A current item that differs from the last shared item and is waiting for the stability period to finish.

Example:

```text
Weapon

Shared:
[Sword of Blood]

Current:
[Blade of Truth]

Pending:
[Blade of Truth]
Pending since: 22:00
```

After the configured stability period, if the current item is still Blade of Truth:

```text
Shared:
[Blade of Truth]

Current:
[Blade of Truth]

Pending:
None
```

Only then is the confirmed slot change sent to other addon users.

---

## 5. First-time acquisition

Slot updates are only useful when a receiver already has a complete baseline for that character.

Therefore, the first time the addon learns a character, it should obtain a **complete snapshot** from one of the available trustworthy sources.

Conceptually:

```text
No Bob record
    |
    +-- Bob is online and participating -> obtain Bob's complete current snapshot
    |
    +-- Bob can be inspected -> obtain a complete inspected snapshot
    |
    +-- Bob is offline -> ask once whether an online guild addon user has a complete cached copy
    |
    +-- nobody has one -> show No data
```

Once that complete snapshot exists, future confirmed changes can normally be handled incrementally.

---

## 6. Delayed gear commit / stabilization rule

A changed item is not immediately broadcast.

The addon should use a **per-slot stability window**, with **5 minutes as the default**.

### Example: temporary change

```text
Last shared weapon:
Sword of Blood

22:00
Equip Blade of Truth
-> Weapon becomes pending.
-> Nothing is sent.

22:03
Equip Sword of Blood again
-> Current item matches last shared item.
-> Pending weapon change is cancelled.
-> Nothing is sent.
```

The guild database remains unchanged because the temporary swap was not useful long-term information.

### Example: stable change

```text
Last shared weapon:
Sword of Blood

22:00
Equip Blade of Truth
-> Weapon becomes pending.

22:05
Still wearing Blade of Truth
-> Pending change becomes confirmed.
-> Send one weapon-slot update.
```

Other addon users then update only the weapon slot in their cached record.

---

## 7. The timer is per slot

Each equipment slot has its own pending state and stability period.

Changing one slot must not reset or interfere with the pending timer of another slot.

Example:

```text
22:00 Weapon changes
22:01 Ring 1 changes
22:03 Weapon changes again
```

Result:

```text
Weapon
Pending item: newest weapon
Pending since: 22:03

Ring 1
Pending item: new ring
Pending since: 22:01
```

The ring may become confirmed before the weapon.

---

## 8. Changing a pending slot again

If a slot changes again before its pending period finishes, the stability period for that slot restarts for the newly equipped item.

Example:

```text
22:00 Sword A -> Sword B
Weapon pending timer starts.

22:03 Sword B -> Sword C
Weapon pending item becomes Sword C.
Weapon pending timer restarts.

22:08 Still wearing Sword C
Sword C becomes the confirmed shared weapon.
```

Sword B is never sent because it was never stable long enough to matter.

If the slot returns to the last shared item at any point, the pending change is cancelled entirely.

---

## 9. Normal confirmed slot-change flow

Example starting state:

```text
Alice's cache:
Bob
Head   = Helmet A
Chest  = Chest A
Weapon = Sword A
Sequence = 184
```

Bob equips Helmet B.

For the next five minutes, Helmet B exists only as Bob's local pending Head change.

If Helmet B is still equipped at the end of the stability period, Bob's addon publishes one small confirmed change:

```text
Bob
Sequence = 185
Slot = Head
Item = Helmet B
```

Alice applies it:

```text
Bob
Head   = Helmet B
Chest  = Chest A
Weapon = Sword A
Sequence = 185
```

No complete snapshot is needed.

Bob can then log off and Alice still has the latest confirmed state she received.

---

## 10. Why the sequence/version is useful

The slot update contains the useful data. The sequence/version exists only to tell a receiver whether it missed a **confirmed shared update**.

Temporary local changes that never become confirmed do **not** need to advance the shared sequence.

Example:

```text
Alice currently has Bob sequence 184.

She receives:
Bob sequence 185 -> Head changed
Bob sequence 186 -> Ring changed
```

Everything is fine.

But if Alice has sequence 184 and receives:

```text
Bob sequence 187 -> Weapon changed
```

then Alice knows that confirmed updates 185 and 186 were not received.

She should **not** assume her record is fully current.

Her Bob record becomes:

```text
Incomplete / refresh needed
```

The addon does not immediately start polling for a repair. It waits until Bob's gear is actually needed, or until the user explicitly requests a refresh.

---

## 11. Multiple stable slots may be batched

Several slots may become confirmed within a short period, especially after a gear-set change.

The addon may combine confirmed changes that are ready at roughly the same time into one compact batch:

```text
Bob sequence 205
Changed:
- Head -> Helmet C
- Trinket 1 -> Trinket C
- Trinket 2 -> Trinket D
- Weapon -> Sword C
```

This is still an incremental update. It is not a complete equipment snapshot unless every slot genuinely changed.

The goals are:

- avoid one message for every equipment event;
- avoid sharing temporary swaps;
- keep the distributed cache reasonably current;
- keep network traffic low.

---

## 12. Gear-set swaps

A gear-set swap may change many slots in a few seconds.

Each changed slot enters its own pending state.

If the player keeps the new gear equipped for the stability period, those slot changes become confirmed and may be sent together.

If the player changes back before the stability period finishes, the reverted slots generate no network update.

This means rapid testing, role swaps, or accidental equipment changes should normally remain local unless they become the player's stable equipment.

---

## 13. What happens on logout with pending changes?

Logging out should **not automatically force pending changes to be shared**.

Example:

```text
22:00
Sword A -> Sword B
Weapon becomes pending.

22:02
Bob logs out.
```

Other addon users should keep the last confirmed shared value:

```text
Bob Weapon = Sword A
```

Bob's local addon may remember enough local state to compare equipment again after login, but logging in by itself must not cause a network broadcast.

After Bob returns, if Sword B is still equipped and differs from the last shared weapon, the weapon can enter a new stability period. Only after it remains stable for the required time is Sword B shared.

This preserves the rule that **only stable equipment changes become guild data**.

---

## 14. What if the player confirms a change and immediately logs off?

If the confirmed slot update was received by other addon users, the information survives through their caches.

Example:

```text
Bob has worn Helmet B for five minutes.
Bob publishes Head -> Helmet B.
Alice receives it.
Bob logs off.
```

Alice still has Helmet B and may later provide Bob's complete cached record to another guild member.

If Bob logs off before a pending change becomes confirmed and shared, the older confirmed snapshot remains the guild's last-known state.

This is acceptable. The product promises **best known stable gear**, not perfect knowledge of every temporary item the player equipped.

---

## 15. Repairing an incomplete record

When a user opens a character whose local record is incomplete:

```text
Open Bob
   |
   +-- Bob online + participating
   |      -> obtain one complete current snapshot
   |
   +-- Bob unavailable/offline
          -> make one guild request for a newer complete cached copy
```

If another online addon user has a complete newer copy, that copy can repair the local record.

Once repaired, normal delayed slot-level updates resume.

There is no standing retry loop.

---

## 16. Offline characters

An offline character cannot provide new live gear information.

The addon therefore shows the **best complete last-known confirmed state** available.

Example:

```text
Bob is offline.

You have Bob sequence 190 complete.
Alice has Bob sequence 194 complete.
John has Bob sequence 192 complete.
```

If a repair/request is necessary, Alice's complete sequence 194 copy is the best candidate.

After you receive it, Bob can remain offline and you still have that cached state.

The UI must make clear that offline cached gear is last-known confirmed gear, not a guarantee of the character's present equipment.

---

## 17. Expected freshness states

### Current / synchronized

A complete gear record exists and no missed confirmed update is known.

### Recently observed

A complete snapshot was obtained from a recent direct observation or inspection, but continuous synchronization is not guaranteed.

### Cached

A complete saved snapshot exists, normally for an offline or unavailable character, but it may be older than their real current gear.

### Incomplete / refresh needed

The addon knows one or more confirmed slot updates were missed. The record can be shown cautiously, but it must not be presented as synchronized/current.

### No data

No complete usable gear record exists.

Pending changes are local-only and should not cause remote users to see a special freshness state before they become confirmed.

---

## 18. Network behavior we want

The addon **may send** when:

- a local pending slot change survives the full stability period;
- several confirmed slot changes are grouped into one compact batch;
- another user explicitly requests the player's complete snapshot;
- another user explicitly asks whether a complete cached copy exists for one specific character;
- a requested incomplete record needs one complete repair snapshot.

The addon **must not send merely because**:

- a player briefly equipped another item;
- a pending slot timer is still running;
- a player reverted to their previously shared item;
- the user logged in;
- the user logged out with an unconfirmed pending change;
- the guild roster opened;
- the addon loaded;
- a cached record became older by some number of minutes;
- the addon wants to check whether everyone is synchronized;
- another player has not been seen recently.

---

## 19. Distributed cache behavior

The guild does not maintain one central database.

Each addon user keeps their own local collection of guild gear they have learned.

Over time, multiple online guild members may hold complete copies of the same offline character's last-known confirmed equipment.

That is useful rather than wasteful because those copies provide resilience:

```text
Bob logs off

Alice has Bob complete
John has Bob complete
Sarah has Bob complete

You later need Bob
-> one of them can provide the cached snapshot
```

There is no need for everyone to exchange their entire databases.

---

## 20. Choosing data when several copies exist

When several complete copies are available, prefer the best known state based on:

1. a current snapshot directly from the target character;
2. a complete record with the newest valid confirmed change sequence/version;
3. a recent direct inspection/observation;
4. the newest trustworthy cached copy.

Do not download every older duplicate when one suitable complete copy is enough.

---

## 21. Configuration

The stability delay should be configurable, with **5 minutes as the default**.

Possible user-facing choices may include:

- 1 minute;
- 2 minutes;
- 5 minutes;
- 10 minutes.

The product behavior remains the same regardless of the selected duration:

> A slot change is shared only if the new item remains equipped for the configured stability period.

For MVP, 5 minutes is the recommended default because it filters short-lived gear swaps while still allowing meaningful changes to propagate reasonably quickly.

---

## 22. MVP behavior

For the first usable release, the addon should support this lifecycle:

```text
1. Learn a character once with a complete snapshot.
2. Save that snapshot across relogs.
3. Detect when the local player changes an equipped slot.
4. Keep the changed slot local and pending for 5 minutes by default.
5. If the slot returns to the last shared item, cancel the pending change and send nothing.
6. If the slot changes to another new item, restart that slot's stability period.
7. If the new item remains equipped for the full stability period, confirm the change.
8. Send only the confirmed changed slot(s), not the full gear set.
9. Online addon users apply those confirmed changes to their cached record.
10. Detect if a confirmed update was missed.
11. Mark missed-update records incomplete instead of pretending they are current.
12. Repair an incomplete/missing record only when the character is actually requested.
13. Allow complete cached records to remain useful after the target logs off.
14. Never use recurring guild polling or full-database synchronization.
```

---

## 23. Product rule in one sentence

> **Capture the full gear state once, hold new slot changes locally until they prove stable, share only confirmed slot changes, and repair gaps only when somebody actually needs the data.**
