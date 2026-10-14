# Magpie: Major Feature Blueprint

Status: implementation in progress on Retail 12.x. This document defines the intended behavior and release checks for 17 proposed features; code presence alone does not satisfy the in-game proof gates.

The dev.97 build delivered Source Fusion and the first Living Atlas view. The dev.98 integration adds an Expedition Studio and Now/Next card; opt-in Survey, Replay, and Party panels; an evidence-labeled Warband, Reset, Collection, Phase, and Quest Chain panel; optional Context Director and Sound Compass controls; and a Closest-route filter for Warband-completed quest starts. These paths have local Lua validation, but require visual and performance checks inside WoW before a release claim. Exact in-world Beacon Constellation placement, verified travel transitions, reward links, chain prerequisites, reset metadata, and phase conditions remain dependent on trustworthy client or pack data; their views show a limited or Unknown state when that data is absent.

## Shared Product Contract

- A live detection, a saved pack location, a player observation, and an inferred hint are different evidence classes. Every surface must distinguish them. A saved rare pin never means the rare is alive.
- One canonical location may have several sources. Preserve source details and user overrides while drawing one understandable marker. A matching live detection wins visually.
- Keep off-range locations available to planning, but only create and update visible radar or beacon widgets for the displayed range. Use bounded pools, cached map transforms, event-driven invalidation, and existing layer budgets.
- No broad quest-log polling, per-frame data-pack scans, unbounded history, or automatic retry loops. Expensive work must be incremental, cancellable, and measured against the existing performance governor.
- Retain the current rounded radar, crystal visual language, Title Case labels, hover-only corner tools, launcher, and optional integrations. Put large planning views in a separate Atlas; do not crowd the radar with 17 new buttons.
- A route never silently changes its selected rare during a fight or advances a quest on proximity alone. Keep the existing per-type completion rules and explicit Skip controls.
- SavedVariables need versioned migrations, size caps, and import validation. Missing APIs or optional addons must degrade to a clear limited state without disabling the base radar.
- Combat-state restrictions in Midnight mean these features should use exposed navigation, quest, map, collection, and user-action information. Do not design around protected combat-log inference.

## 1. Expeditions

**Experience.** The player chooses a goal such as finishing a quest chain, clearing specified rares, and collecting specified treasures. A compact Now / Next / Progress card remains readable beside the radar and launcher. The Atlas shows the whole trip and the reason for each proposed stop. The player can lock a stop, skip it, reorder goals, pause, or resume.

**System.** Model a trip as goals and dependency-aware steps with available, blocked, active, complete, skipped, and unknown states. Replan on relevant quest, loot, map, and user events, with a cooldown and stable-stop rule so it does not bounce between nearby candidates. Reuse existing World Focus and type-specific completion behavior.

**Controls and release check.** Choose categories, current-zone or cross-zone travel, preferred travel method, detour tolerance, and whether suggested stops require confirmation. An unmapped or unconfirmed step must show why it cannot auto-advance. Changing zoom must never delete the trip.

## 2. Living Atlas

**Experience.** Open a themed planning layer over the world map. It shows live detections, selected pack notes, quest objectives, observed positions, routes, and completion status using visibly different shapes and a clear legend. Selecting an Atlas marker highlights the same radar destination; multi-select creates an Expedition or draft route.

**System.** Reuse one canonical location registry instead of separately reconciling every view. Load only the visible map and parent-map data. Cluster dense markers by screen distance and expand on hover or zoom. Preserve map/floor identity and source attribution.

**Controls and release check.** Filters for type, source, confidence, completion, and character. The map must stay responsive with a dense pack; hidden layers must do no drawing work. Closing the Atlas restores the original map interaction.

## 3. Party Hunt

**Experience.** Group members with Magpie may share a fresh sighting, a chosen destination, or an Expedition stop. A shared report has the sender, age, map, and an expiry badge. It is never styled as a locally verified live detection until the local client sees it.

**System.** Opt-in, versioned addon messages with deduplication, rate limits, and expiry. Send only small location and identity records; do not stream movement, inventory, or full routes continuously. Mark phase or instance compatibility as unknown when it cannot be verified.

**Controls and release check.** Receive Off / Party / Raid, share sightings, share chosen stop, and ignore sender. Disconnects and malformed messages must be harmless. No group chat spam, silent background broadcast, or automatic waypoint hijacking.

## 4. Travel-Aware Routes

**Experience.** A 600-yard treasure beyond a mountain can rank behind a 900-yard treasure on an open road. The route preview shows estimated travel cost and why it chose an entrance, portal, flight point, or zone transition.

**System.** Use a small graph of verified transitions and approach nodes, plus movement-mode weights. Straight-line yards remain the fallback and are labeled as such. Cache paths by map and travel mode; recalculate on travel-state or goal changes, not every render.

**Controls and release check.** Choose direct, ground, flying, or automatic estimates; allow avoiding known transitions. A missing or contradictory graph edge must fall back cleanly rather than trap the route or claim a walkable path.

## 5. Survey Mode

**Experience.** A subtle coverage layer shows parts of the current zone the character has crossed and nearby unvisited areas. A user can start a sweep, pause it, and see a coverage estimate without confusing unexplored ground with an undiscovered treasure.

**System.** Record coarse, bounded map cells on movement intervals, ignoring teleports and invalid coordinates. Compress or prune old coverage by zone. Reuse the existing trail only as visual history, not as proof that every point along a straight segment was visited.

**Controls and release check.** Per-character or shared coverage, opacity, cell size, and optional nearby-unvisited cue. It must work when the radar is minimized and must not add per-frame SavedVariable writes.

## 6. Beacon Constellation

**Experience.** A few restrained floating markers identify the current stop, next stop, and relevant cave entrance. The active marker gets the strong crystal treatment; secondary markers remain quiet. Hover gives name, source, distance, and step.

**System.** First prove that the current Retail client exposes stable, permitted projection and altitude data for the desired display. Cap the visible set, reuse textures, throttle position updates, and cull offscreen markers. Never present a screen-space approximation as an exact 3D object location.

**Controls and release check.** Off / Current / Current + Next / Up to a small cap, scale, opacity, and combat quiet mode. If projection is unreliable, use the existing single waypoint and Bearing Bar as the fallback. No permanent world clutter or frame-rate spike.

## 7. Context Director

**Experience.** The radar can temporarily adopt a travel, cave, questing, treasure-hunt, or group view. A small label explains the active context; a manual lock holds the player's preferred view until released.

**System.** Rules change a temporary view overlay, not saved base preferences. Events drive transitions with hysteresis so brief mount or zone changes do not flicker the UI. Protected changes wait until allowed; failure returns to the previous view.

**Controls and release check.** Enable individual contexts and choose their preset, range, marker filters, and audio behavior. A manual zoom or filter action must take priority for a configurable interval.

## 8. Source Fusion

**Experience.** Select several HandyNotes packs or Zygor POIs, yet see one marker per matching place. A detail card lists contributing sources, different names or coordinates, and which one currently supplies the display point. The user can prefer a pack for a zone.

**System.** Normalize IDs, names, map/floor, type, and coordinates; merge only with conservative matching. Keep conflicting points separate when identity is uncertain. A local live detection always wins the visible marker. Cache provider snapshots by map and invalidate only the changed source.

**Controls and release check.** The current single-source behavior remains the default until Fusion is enabled. Provide pack selection, per-zone priority, conflict distance, and a source-inspection view. Dense packs cannot cause unbounded matching or duplicate drawing.

## 9. Warband Hunt Board

**Experience.** A board shows which character still has a selected goal available and which rewards are already shared. It can suggest the character most ready for an Expedition, with the last-seen time beside offline character data.

**System.** Store per-character snapshots and separate character-specific completion from Warband-wide collections. Update on login and relevant events; do not imply live knowledge of an offline character. Existing account-wide loot observations remain evidence, not automatic eligibility proof.

**Controls and release check.** Account versus character view, favorite characters, and stale-data threshold. Unknown eligibility must say Unknown. Never overwrite one character's quest state with another's.

## 10. Reset Planner

**Experience.** A small queue tells the player which saved goals reopened today or this week. It can add eligible goals to an Expedition, while completed one-time content stays out of the queue.

**System.** Classify confirmed daily, weekly, one-time, and unknown resets only from reliable flags or explicit user rules. Reevaluate at login and known reset transitions. A timer alone must not prove an object is available.

**Controls and release check.** Category filters and quiet notifications. Each item shows Confirmed, Expected, or Unknown. Incorrect or absent reset metadata must never silently mark a goal complete or available.

## 11. Quest Chain X-Ray

**Experience.** Click a desired quest or campaign goal to see known prerequisite steps, the active step, and why the next one is blocked. Selecting a mapped step sends it to World Focus or an Expedition.

**System.** Use current quest state plus a versioned prerequisite source if one is available. Keep missing edges explicit; do not infer a full chain from quest titles. Resolve objectives through the existing quest-point cache and bounded remote-map lookup.

**Controls and release check.** Show main story, side quests, or chosen chain. No broad quest-log scan, no phantom objective coordinates, and no automatic step completion merely because the player reached a point.

## 12. Treasure Playbooks

**Experience.** A complex treasure displays a concise sequence: reach entrance, interact with mechanism, approach chest, loot. The current step appears below the radar; the entrance is pinned first when relevant.

**System.** Accept explicit route metadata from a pack, a vetted bundled recipe, or the player's own steps. Mark each step as location, interaction, quest condition, or manual instruction. Auto-advance only when a trustworthy event confirms it; otherwise offer Next Step.

**Controls and release check.** Show instructions, skip or reset step, and choose whether to use a playbook automatically. The final treasure retains the existing 3-yard/loot behavior. A free-text note must not be parsed into guessed coordinates.

## 13. Route Studio

**Experience.** Inside the Atlas, add, drag, reorder, group, and label stops. Preview the trip before activating it. Import/export a human-reviewable route and undo edits.

**System.** Versioned, data-only route schema with strict size and coordinate validation. Saved edits are separate from the active route until Apply. Keep cross-map stops and source references stable through a pack refresh.

**Controls and release check.** Manual order versus optimization, loop back, skip completed, and route sharing. Imported data must never execute code or write beyond the route store. Undo and Cancel restore exactly the prior route.

## 14. Collection Lens

**Experience.** Highlight locations tied to mounts, pets, toys, or appearances the player wants. The marker distinguishes uncollected reward, already collected reward, and unknown linkage. A reward card links the destination to the relevant collection entry.

**System.** Require a reliable item/reward-to-source association and query collection state through available client APIs. Keep account-wide collection state separate from character eligibility. Cache lookups and invalidate on collection changes.

**Controls and release check.** Select reward categories and hide collected rewards. No invented drop rates, guaranteed-loot labels, or false claim that a specific rare is alive.

## 15. Phase Lens

**Experience.** When a pack point is absent in the current quest phase, the radar can label it as a possible phase mismatch and show what evidence that warning is based on. Locally detected targets always remain visible.

**System.** Record only known quest-condition metadata and bounded player observations. Treat an unexposed phase as Unknown. Never infer a global phase ID from mere absence of a vignette.

**Controls and release check.** Show, dim, or hide only explicitly phase-conditioned saved points; a separate setting controls heuristic warnings. The detail card must explain the condition and offer an override.

## 16. Sound Compass

**Experience.** Optional, sparse audio cues tell the player when the active destination moves to the left or right of their view and when they approach it. A text equivalent always remains on the arrow and route card.

**System.** Prove permitted speech and audio APIs on the target client before selecting a sound design. Use angle buckets, hysteresis, and cooldowns so turning or skyriding does not produce rapid repeats. It speaks only the active route, not every map note.

**Controls and release check.** Off by default, volume, cue frequency, speech versus tones if supported, and combat/instance quiet mode. Muting must take effect immediately; unavailable speech falls back to tones or text without errors.

## 17. Signal Replay

**Experience.** Rewind a short session timeline in the Atlas to find where a rare appeared, where the player turned, or which treasure marker vanished. Clicking a past signal can create a saved investigation pin, never a fake live detection.

**System.** Keep a small ring buffer of meaningful changes and sparse player samples. Mark timestamps and source type, merge repeated events, and clear the session buffer on logout unless the player explicitly saves an excerpt.

**Controls and release check.** Recording toggle, retention window, and save/delete controls. Fixed memory limit, no per-frame disk writes, and playback that cannot alter the current route until the player chooses a past point.

## Access, Defaults, And Feasibility

Every feature must be reachable through a visible control or WoW Key Bindings, with searchable Title Case settings. Expeditions belong in the existing route chooser; Source Fusion belongs in Map Data; the Atlas opens from a clearly labeled map/radar action; route editing lives inside the Atlas. Secondary systems get compact subpages rather than new top-level tabs or a forest of radar-corner buttons. The launcher-only view still exposes the active trip and an Atlas entry on hover or right-click.

The Atlas is available without enabling an overlay and does no work while closed. Source Fusion starts in the current single-source mode until the player selects additional packs. An Expedition starts only after choosing goals. Party broadcast, Sound Compass, and persistent Signal Replay are opt-in. Context Director never silently changes saved preferences. New defaults must be shown in the relevant settings page and in a short first-use explanation; no feature is reachable only by a slash command.

| Capability to prove | Smallest useful proof | Fallback if unavailable |
| --- | --- | --- |
| Multiple map-pack sources | Read two enabled packs on one map, merge one exact duplicate, and keep one conflicting point separate within a measured time budget. | Current single selected source. |
| Cross-zone quest goals | Resolve one known mapped objective from an adjacent map without broad quest-log iteration. | Keep the goal but show its location as unknown. |
| Travel transitions | Route through one explicit cave entrance or zone transition and compare with straight-line order. | Straight-line distance labeled as an estimate. |
| World projection and altitude | Place one stable non-combat destination marker while moving and skyriding; profile it. | Existing Blizzard waypoint, route arrow, and Bearing Bar. |
| Group reports | Exchange one versioned sighting with a consenting party member; reject a duplicate and malformed payload. | Local-only radar. |
| Offline character status | Read a saved snapshot after a character switch and preserve account versus character state. | Current-character view with stale data labeled. |
| Reset, phase, quest-chain, and reward metadata | Verify one real example of each from exposed APIs or a trusted optional data source. | Unknown status and manual notes, never a guessed answer. |
| Speech or directional audio | Verify a permitted cue, immediate mute, and stable rate while turning quickly. | Text route card and existing alerts. |

## Build Sequence And Proof Gates

1. **Shared foundation:** canonical location identity, evidence class, source provenance, route-step state, bounded cache, and migration tests. Preserve all existing views during this refactor.
2. **Flagship vertical slice:** Living Atlas + Source Fusion + a simple Expedition with current-zone rare, treasure, and quest goals. Prove duplicate handling, stable stops, map responsiveness, and radar-to-Atlas synchronization in WoW.
3. **Navigation depth:** Travel-Aware Routes, Treasure Playbooks, Quest Chain X-Ray, Route Studio, then Beacon Constellation only after its projection proof.
4. **Personal intelligence:** Survey, Warband Board, Reset Planner, Collection Lens, Phase Lens, and Signal Replay. Each ships with explicit evidence labels and storage limits.
5. **Optional coordination and access:** Party Hunt, Context Director, and Sound Compass with opt-in controls and graceful fallbacks.

Before a feature ships, verify its smallest supported UI size, launcher-only state, Atlas open/closed state, all exposed popups, empty/unknown data, zone transition, combat restrictions, and optional-addon absence. Use fixture tests for matching, migrations, and routing invariants, plus in-game profiling with a dense data pack. Record measured CPU and memory before and after each phase. No feature should rely on a broad scan that can freeze the client.

## External Feasibility Notes

- Blizzard's Midnight addon guidance says combat state can include secret values that addons may display but cannot inspect for arbitrary logic: https://worldofwarcraft.blizzard.com/en-us/news/24246290
- Blizzard describes Warband-wide collections alongside character-specific exceptions. The Board must represent both: https://worldofwarcraft.blizzard.com/en-us/news/24115313
- Multi-marker world projection, sound or speech APIs, phase evidence, reset metadata, quest-chain prerequisites, collection-source associations, and travel transitions each need a small executable proof on the installed Retail client before a full implementation is promised.
