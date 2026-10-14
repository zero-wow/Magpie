# Magpie 0.1.0-dev.76

This build adds 15 capabilities, fixes 15 failure paths, and polishes 15 interactions. It keeps the public base version at 0.1.0.

## New capabilities

1. Show nearby live treasures in the optional Bearing Bar.
2. Show treasure locations from the selected map-data pack there too.
3. Show mapped cave entrances with their own marker.
4. Choose rare, loot/cave, and quest bearings independently.
5. Right-click a crowded bearing to cycle the points at that heading.
6. Prioritize favorite map notes when the Bearing Bar is crowded.
7. Click a quest bearing to focus its Blizzard waypoint.
8. Click a saved-note bearing to focus its waypoint or linked treasure path.
9. Shift-click any bearing category to pin that exact point directly.
10. Pause and resume Auto Route without losing visited stops.
11. Skip the current quest while an automatic quest route is running.
12. Clear the current focused waypoint from the route menu or a key binding.
13. Choose Standard, Balanced, or Low CPU update rates.
14. Rescan selected map-pack data immediately from Status.
15. Bind radar, settings, bearings, routing, nearest-point routes, Zygor pinning, and clear-focus actions in WoW's Key Bindings.

## Fixes

1. Pause a display that consumes too much cumulative CPU time, even when no single update stalls.
2. Skip route candidate calculations until player world coordinates are valid.
3. Avoid distance arithmetic during route sync when the player position is temporarily unavailable.
4. Ignore malformed map notes with missing coordinates during live-note duplicate checks.
5. Ignore incomplete guide and saved-note coordinates when building route candidates.
6. Only suppress a saved bearing as a live duplicate on the same map.
7. Keep a quest's actual map when its bearing or diamond is selected.
8. Keep a quest's actual map when building nearest-route candidates.
9. Avoid concatenating a missing source ID on a cave-entrance note.
10. Keep guiding a quest after objectives finish until the quest is turned in.
11. Clear the addon's final owned waypoint after the route reaches its last stop.
12. Prevent an arrival from advancing a paused route.
13. Refuse to resume a route after another addon or the player replaces its waypoint.
14. Preserve pending quest-map requests across ordinary quest-log updates.
15. Clear stale pack-source caches during a manual rescan.

## Interface polish

1. Give treasure bearings a dedicated chest image.
2. Give cave entrances a dedicated arch image.
3. Tint both images with the selected theme's marker colors.
4. Underline the bearing that matches the current focused waypoint.
5. Label favorite points in the bearing tooltip.
6. Label the current waypoint in that tooltip.
7. Mark which point is selected in a crowded bearing's hover list.
8. Show click, Shift-click, and right-click instructions on the bearing itself.
9. Summarize visible bearings by rare, loot, cave, and quest counts.
10. Use an all-category empty message when nothing is in range.
11. Explain when all Bearing Bar marker categories are turned off.
12. Label the route control Start, Pause, or Resume according to its actual state.
13. Keep the larger route menu's controls inside its frame with a visible gutter.
14. Use Title Case throughout the new WoW key-binding labels.
15. Rank settings-search results by relevance and remove duplicate choices.

Validation: all 14 Lua tests pass, all 16 top-level Lua files compile, the binding XML parses with one header, and both new 64×64 TGA assets open. WoW rendering and live API behavior still require an in-game reload and check.
