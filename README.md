CREDIT IS TO OSIRISOFTHGINTERNET , all I did was add Optimisations.

# Absolute's Laboratory

This is a modified build of [Absolute's Laboratory](https://www.nexusmods.com/baldursgate3/mods/) 

Three files are new, nine existing files were modified, and 134 files are byte-for-byte identical to the base release (all of Monster Lab, the Mutators/Selectors library, the Inspector, the IDE/Reactivex helper libraries, and so on were untouched). Everything described here lives in `ScriptExtender/Lua/`.

## Why these changes exist

The short version: the base mod applies your active Mutation Profile to *every eligible entity on a level* the moment it loads, whether or not that entity ever actually does anything. On a level with a lot of potential enemies, that's a lot of up-front work for creatures you may never fight. These changes add an opt-in "Combat Only" mode that defers mutation until an entity actually enters combat, plus the supporting infrastructure that mode needs (correct player-combat detection, debounced batching, a lighter-weight passive-duplicate check, manual recovery tools, and status feedback) so that deferring the work doesn't just trade one performance problem for a subtler one.

---

## New features

### 1. Apply Trigger: `Always` / `Combat Only` / `Off`

**Where:** Profile Execution Hub (MCM), new setting next to Execution Method and Status Window. Backing config key: `ConfigurationStructure.config.mutations.settings.profileExecution.applyTrigger`, default `"Always"`.

- **Always** (the base mod's only behavior) — unchanged: every eligible entity on the level gets mutated as soon as it loads.
- **Combat Only** — skips that level-load sweep entirely. Nobody is touched just for existing on the level. Instead, each entity is mutated the instant it actually enters combat, batched with anyone else joining the same fight (see the `EnteredCombat` rewrite below). Enemies that never fight you are simply never processed.
- **Off** — Lab does nothing automatically at all, not even its normal safety-net Undo pass when no Profile is active. This is meant for someone who has already confirmed the level is clean (via Undo or Force Clean, below) and wants Lab to sit completely idle. The manual Apply/Undo buttons still work in every mode, since those are explicit user actions rather than something running in the background.

This required rewriting the `EnteredCombat` listener in `Server/Mutations/MutationProfileExecutor.lua`, which previously queued *any* entity that entered combat without a mutation record, with no regard for whether that entity would have even been eligible, and no regard for whether the fight involved the player at all. Two problems came from that:

- **Eligibility wasn't checked before queuing.** A party member or summon joining combat would still get queued for an Apply pass, just to be filtered out once the pass actually ran. Under Combat Only that meant a real (if wasted) Apply pass — and a status window pop-up — every single time an ally or summon joined any fight, not just when something was actually mutation-eligible.
- **Combats that don't involve the player still fire `EnteredCombat`.** BG3 can run combats that have nothing to do with the party at all — two enemy factions fighting each other, a scripted fight elsewhere on the level — and the event fires for those too. The rewrite tracks, per `Combat` guid, whether the host or a party member has actually entered that specific combat (`playerInvolvedCombats`), and the debounced Apply only runs if that's true. A `CombatEnded` listener cleans up the per-guid tracking tables afterward so they don't grow unbounded for the rest of the session.

The debounce window itself was also changed from a single global 300ms timer to one timer *per combat guid*, so two unrelated fights starting close together in time don't get their entity lists merged into a single Apply call.

### 2. Manual "Apply Mutations Now" / "Undo Mutations Now" buttons

**Where:** Mutations MCM tab, next to "Open Profile Execution Hub".

Lets you force a full re-apply or a full undo of the current level without saving and reloading — useful for testing a Profile change immediately, or for recovering from a weird state without restarting the level. These send `Channels.ManualApplyMutations` / `Channels.ManualUndoMutations` (new channels, see below) to the server, which calls the same `ExecuteProfile` / `UndoAllMutations` entry points the automatic triggers use, so they respect whatever Execution Method and Status Window settings are already configured and work identically regardless of the current Apply Trigger mode, including `Off`.

Implementing "Undo Mutations Now" required splitting the undo logic that used to live inline inside `ExecuteProfile` (only reachable when no Profile was active) out into its own `MutationProfileExecutor:UndoAllMutations` function, so it could be called on demand as well as automatically.

### 3. "Force Clean By Folder..." — a recovery tool (`ForceCleanWindow.lua` + `ForceCleanUtility.lua`, both new files)

The normal Undo relies on a per-entity save variable (`Absolutes_Laboratory_Mutations`) that records exactly what was changed and what to put back. If that variable is lost — most commonly because Absolute's Laboratory itself was fully uninstalled while mutated entities still existed in the save, and the game was then saved/reloaded in that state — the normal Undo has nothing left to work from.

Force Clean doesn't try to reconstruct that lost record (there's no reliable way to, since some mutators use randomness that isn't reproducible after the fact). Instead, for a Mutation Folder you pick, it works out every Passive, Status, and Spell that folder's mutators *could* have granted — loose entries plus anything in the Lists they reference, resolved recursively through linked Lists — then checks every character currently loaded on your level directly against that set and strips whatever's actually present.

This is explicitly a broader, safer-by-construction approach rather than a precise one, and it says so up front: it only covers PassiveList/StatusList/SpellList mutators (Ability/Health/Level/Class/Equipment/Boosts/Action Resources/Progressions/PrepPhaseMarker mutators overwrite values rather than adding something removable by name, so there's no safe way to detect or revert them this way), it can't restore Spells a config *removed* from a character, it doesn't walk vanilla class-progression auto-population, and it only affects your current level — revisit other affected levels and run it again. All of this is surfaced directly in the tool's own window before you use it, not buried in a comment.

The resolution and per-entity scan are both deliberately bounded (`MAX_LIST_VISITS`, tick-batched processing) specifically because an earlier version of this kind of walk could hang the game for a long time on a deeply cross-linked Folder, like a class-conversion folder that links every subclass variant back into a shared vanilla spell pool.

### 4. Execution status window (`MutationExecutionStatusWindow.lua`, new file)

Brings back the small on-screen indicator ("Mutations are being applied/undone") that existed before Absolute's Laboratory 1.12, which got dropped when the Profile Execution Hub replaced its predecessor. Driven by a new `Channels.MutationExecutionStatus` broadcast from the server (`MutationProfileExecutor:broadcastStatus` / `:startStatusTicker`, ticking every 500ms while an Apply or Undo is running) and a new "Status Window" setting in the Execution Hub (`Detailed` / `Simple` / `Off`). Setting it to `Off` fully skips the broadcast server-side, not just the client-side render, so there's no wasted network traffic for a window nobody wants to see.

### 5. Instant (Legacy) execution mode

**Where:** Profile Execution Hub, "Execution Method" setting. Config key: `executionMode`, `"TickBased"` (default) or `"Instant"`.

The base mod always spreads entity processing across multiple game ticks via its permit-based `DripScheduler`, to keep the game responsive. This adds the option to skip that scheduler entirely and process every eligible entity in one uninterrupted burst — closer to how pre-1.12 versions of Lab behaved. It's faster overall but can cause a brief hitch, so it's opt-in rather than the default. Both `ExecuteProfile` and the new `UndoAllMutations` respect this setting.

---

## Bug fixes

### Passive Duplicate Remover stutter (the main one)

This was the result of real back-and-forth debugging against reported in-game stutter, not a guess — the final state was reached over two corrections after the first fix turned out to be insufficient.

The Passive Duplicate Remover runs a 6-second self-rescheduling cleanup loop (`resetTracker`) while it's subscribed to passive-container changes, and is supposed to unsubscribe and stop that loop once there's been no Mutation activity for a while. Two separate bugs let that loop outlive its intended lifetime:

1. **Stale-chain resurrection.** The original "is a loop currently active" tracking was a plain boolean. If a second `RunBriefly` call started (e.g. a second combat beginning) before the first one's grace window had elapsed, the first chain's already-scheduled timer could fire *after* the second chain had already set the flag back to "active," making the old chain think it should keep rescheduling itself alongside the new one. Across a long play session with repeated combats, this could stack up multiple concurrent 6-second loops instead of at most one. Fixed by replacing the boolean with a monotonically rising `loopToken`: each chain captures the token value current when *it* started, and only reschedules itself if that token still matches the live one — both loading and unloading the deduplicator bump the token, so a stale chain can never be mistaken for current.
2. **Lazy teardown during idle time.** The grace-window timeout used to just set a `"Paused"` flag, which the subscription's handler would only notice the *next* time a passive-container event fired. During active combat that's immediate; during genuine idle time, with no combat and no gear/status changes, that next event might never come — leaving the subscription (and its 6-second loop) alive far longer than the intended ~15-second grace window. Fixed by having the timeout call a new `unloadDeduper()` directly, which tears the subscription down unconditionally instead of waiting for a future event that might not arrive.

On top of both fixes, `MutationProfileExecutor:completionFunc` now calls the new `RunBriefly(15000)` instead of an unconditional `advanceState("Running")`, so the deduplicator only stays subscribed for a short, bounded window after a Mutation pass — long enough to catch a duplicate passive that pass itself might have introduced — rather than remaining subscribed to every passive-container change on the level indefinitely.

### Combat-entry eligibility and player-combat gating

Already covered under Apply Trigger above — these were originally diagnosed as part of the Combat Only work, but they're genuine correctness fixes independent of that setting: without them, Lab could queue (and, under certain states, fire) an Apply pass for entities that were never eligible, or for combats the player wasn't part of at all.

### PassiveListMutator `table.insert` crash (merged from the official 1.13.6 update)

`table.insert(replaceMap.passiveLists[statReplacement])` was being called with only the table argument and no value — invalid Lua that would error at runtime when processing a replacement entry for a passive list with a spell-list dependency. Fixed to `table.insert(replaceMap.passiveLists[statReplacement], toReplace)`, matching the upstream author's own 1.13.6 changelog entry for this exact issue.

### Party Follower eligibility (merged from the official 1.13.5 update)

`isEntityEligible` and the `CharacterJoinedParty` listener were updated so Party Followers (as opposed to full party members) are properly eligible for Mutations once they join, using the new `IsPartyFollower` Osiris check and the `IsPartyFollowerSelector` selector, and so a follower that already had Mutations applied before joining gets those undone on join rather than being left mutated twice over.

---

## Supporting infrastructure (smaller, in service of the above)

- **`Shared/Channels.lua`** — five new `Ext.Net` channels: `ManualApplyMutations`, `ManualUndoMutations`, `MutationExecutionStatus`, `ForceCleanByFolder`, `ForceCleanResult`.
- **`Shared/Configurations/MutationsConfig.lua`** — three new settings backing the above: `executionMode`, `statusView`, `applyTrigger`.
- **`BootstrapClient.lua` / `BootstrapServer.lua`** — `Ext.Require` entries for the three new files (`MutationExecutionStatusWindow.lua`, `ForceCleanWindow.lua` on the client; `ForceCleanUtility.lua` on the server).
- **`MutationProfileExecutor`** gained `progress` tracking (`processed`/`total` counts) and a `statusPayload`/`broadcastStatus`/`startStatusTicker`/`stopStatusTicker` set of helpers, all feeding the new status window and existing purely to support it — they don't change what gets mutated or when.

---

## Compatibility note

Every change above is additive or corrective — no existing Mutation Profile, Folder, or save data format was changed. A save that worked on the base mod will continue to work here; the new settings all default to the base mod's original behavior (`Always` trigger, `TickBased` execution, `Simple` status view) so nothing changes for you unless you opt into it via the Profile Execution Hub.
