local _, addon = ...
if type(addon) ~= "table" then return end

-- Button Tray: while the Minimap Underlay is on, the radar's corner buttons
-- and the minimap's buttons are gathered off the face into one small drawer
-- that slides out from behind a lip on the radar's side.
--   * Two sets, one shown at a time: "radar" (panel.hoverTools from
--     UI/Radar.lua plus the underlay toggle) and "minimap" (LibDBIcon buttons
--     and Blizzard's calendar, tracking, mail/orders indicator, landing page
--     and addon compartment). A flip button in the tray swaps the set; the
--     choice is saved in vignetteRadarButtonTraySet.
--   * Every gathered frame is snapshotted (parent, points, scale, strata,
--     level, alpha, shown, mouse, plus LibDBIcon drag scripts, mouseover fade,
--     border and fixed strata) and put back exactly when the underlay turns
--     off, the radar hides or the setting turns off. The underlay calls
--     ButtonTray.OnUnderlay from its borrow and give-back (UI/MinimapUnderlay
--     NotifyTray), so both stay out of combat. Protected frames never move in
--     combat; they wait for PLAYER_REGEN_ENABLED.
--   * Owners that move a gathered frame back (LibDBIcon updatePosition, the
--     landing page offset, Edit Mode re-anchoring the indicator) are undone by
--     SetPoint/SetParent post-hooks, once per call, behind a guard.
--   * The drawer is a clipped slot like UI/Tray.lua's, beside the face on the
--     side away from the radar tray (right unless the tray is docked right),
--     with a handle made by Tray.CreateHandle in the tray's handle style.
--     Hidden by default each session; click the lip to slide it out, click
--     again, click elsewhere or enter combat to slide it in (the lock in the
--     tray header, vignetteRadarButtonTrayLocked, keeps it out).
--   * Hand-made (non-LibDBIcon) minimap buttons are found by a conservative
--     scan of Minimap and MinimapCluster children (and theirs, one level):
--     named Buttons, roughly square, SCAN_MIN..SCAN_MAX px, mouse on, not
--     Blizzard's (NOT_ADDON), not ours. Rescanned when the tray opens and a
--     moment after ADDON_LOADED. Advanced setting vignetteRadarButtonTrayScan.
--   * Ignore list vignetteRadarButtonTrayIgnore[name] = true (hidden): those
--     minimap buttons are left alone (not gathered, not hidden by the
--     underlay's chrome). Alt+Right-click a minimap button in the tray, or
--     /magpie buttons [list | reset | ignore <name> | unignore <name>].
--   * Each cell sits on a rounded plate (the theme background, lifted) that
--     takes an accent tint on hover; repainted on theme change.
--   * Edit Mode (EventRegistry "EditMode.Enter"/"EditMode.Exit") gets the
--     Blizzard frames back while it is open; they are gathered again after.
--   * Fixed 3-column grid, row-major, inside a clipped viewport. Its height
--     is the rows the radar set needs (capped by the face), so a flip never
--     resizes the drawer; extra rows scroll one row per wheel notch. The
--     config tool is pinned in the header left of flip and lock, in both sets.
--   * Press and hold (or press and drag 6 px) a button to move it: a ghost
--     follows the cursor and swallows the release (no click forwarding, no
--     foreign script replaced), the others shift to show the gap, the viewport
--     scrolls at its edges. Esc, right-click, a drop outside, combat, a flip or
--     closing the tray cancels. Order saved per set by stable name in
--     vignetteRadarButtonTrayOrder; /magpie buttons order [reset [radar|minimap]].
--   Trace topic "buttons": gather, restore, re-pin, flip, open, close, skips,
--   pickup, reorder, cancel.
local ButtonTray = {}
addon.VignetteRadarButtonTray = ButtonTray

local type, pcall, ipairs, pairs, tostring = type, pcall, ipairs, pairs, tostring
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

local ENABLE_KEY, MINIMAP_KEY, SET_KEY = "vignetteRadarButtonTray", "vignetteRadarButtonTrayMinimap",
    "vignetteRadarButtonTraySet"
local SCAN_KEY, LOCK_KEY, IGNORE_KEY = "vignetteRadarButtonTrayScan", "vignetteRadarButtonTrayLocked",
    "vignetteRadarButtonTrayIgnore"
local ORDER_KEY = "vignetteRadarButtonTrayOrder"
-- Fallback scan: size window (px, own units), how far from square, and the
-- wait after ADDON_LOADED (bursts at login collapse into one scan).
local SCAN_MIN, SCAN_MAX, SCAN_RATIO, SCAN_DELAY = 18, 42, 1.4, 1
local PLATE_TEXTURE = "Interface\\AddOns\\Magpie\\Media\\control-rounded-square.tga"
-- Blizzard frames the scan never takes (names verified in Blizzard_Minimap,
-- Blizzard_HybridMinimap, Blizzard_TimeManager and QueueStatusFrame XML),
-- plus older client names some addons still re-create.
local NOT_ADDON = {
    Minimap = true, MinimapCluster = true, MinimapBackdrop = true, MinimapCompassTexture = true,
    HybridMinimap = true, ExpansionLandingPageMinimapButton = true, GameTimeFrame = true,
    AddonCompartmentFrame = true, TimeManagerClockButton = true, QueueStatusButton = true,
    MinimapZoneTextButton = true, MinimapZoomIn = true, MinimapZoomOut = true, MiniMapTracking = true,
    MiniMapMailFrame = true, MiniMapWorldMapButton = true,
}
ButtonTray.NOT_ADDON = NOT_ADDON
-- Cell pitch and padding in the radar's units (the tray wears the radar's scale).
local CELL, GAP, PAD, HEADER, FLIP_SIZE = 22, 3, 6, 22, 16
local COLUMNS, THUMB = 3, 3
local PITCH = CELL + GAP
local GRID_WIDTH = COLUMNS * CELL + (COLUMNS - 1) * GAP
-- The radar tool that stays in the header (never scrolls, never moves).
local PINNED = "config"
-- Reorder: move threshold (UIParent units), press-and-hold time, auto-scroll
-- band and periods (outer / inner half), ghost and lifted-cell alphas.
local DRAG_PX, HOLD_SECONDS, EDGE, EDGE_SLOW, EDGE_FAST = 6, .35, CELL, .18, .09
local GHOST_ALPHA, LIFTED_PLATE, LIFTED_ALPHA = .85, .35, .6
local SLIDE_SECONDS, FOLLOW_SECONDS, MIN_FIT, MARGIN = .22, .1, .6, 8
local OPPOSITE = { right = "left", left = "right" }
-- Blizzard's minimap extras, in tray order. IndicatorFrame is taken whole:
-- its mail and crafting-order children call GetParent():Layout().
local BLIZZARD = {
    { name = "GameTimeFrame", get = function() return _G.GameTimeFrame end },
    { name = "Tracking", get = function() return _G.MinimapCluster and _G.MinimapCluster.Tracking end },
    { name = "IndicatorFrame", get = function() return _G.MinimapCluster and _G.MinimapCluster.IndicatorFrame end },
    { name = "ExpansionLandingPageMinimapButton", get = function() return _G.ExpansionLandingPageMinimapButton end },
    { name = "AddonCompartmentFrame", get = function() return _G.AddonCompartmentFrame end },
}
ButtonTray.BLIZZARD = BLIZZARD

local adopted = {} -- frame -> record { kind, set, name, order, snap, cell }
local lists = { radar = {}, minimap = {} } -- frames per set, in tray order
local queued = {} -- frame -> { kind, set, name, order } waiting for combat to end
local hooked = {} -- frames whose SetPoint/SetParent/OnShow hooks are in
local slot, content, groups, lip, flip, lock, emptyText, driver
local viewport, thumb, ring, ghost
local scrollRows = { radar = 0, minimap = 0 } -- rows scrolled, kept per set across flips
local current = { set = nil, shown = {}, total = 0, visible = 1 } -- last layout of the shown set
local drag -- reorder state: nil (idle), "pressed" or "dragging"
local Cancel -- ends a reorder without a change (defined with the reorder code)
local progress, target, from, elapsed, follow = 0, 0, 0, 0, 0
local underlayOn, gathered, pinning, dirty, retry, libHooked = false, false, false, false, false, false
local editing, scanWait = false, nil
local panelRef
local signature = {}
local spare = { radar = {}, minimap = {} } -- given-back cells, reused per set
local skipped = setmetatable({}, { __mode = "k" }) -- frame -> last traced scan skip reason

local function Settings() return addon.GetSettings() end

local function Trace(fmt, ...)
    local trace = addon.Trace
    if trace and trace.Log then trace.Log("buttons", fmt, ...) end
end

local function Locked()
    if addon.Bus and addon.Bus.InCombat and addon.Bus.InCombat() then return true end
    local lockdown = _G.InCombatLockdown
    if type(lockdown) ~= "function" then return false end
    local ok, value = pcall(lockdown)
    return ok and value == true
end

local function Protected(frame)
    if not (frame and frame.IsProtected) then return false end
    local ok, value = pcall(frame.IsProtected, frame)
    return ok and value == true
end

function ButtonTray.IsEnabled() return Settings()[ENABLE_KEY] ~= false end
-- True when the tray also takes the minimap's buttons (the underlay then
-- leaves LibDBIcon buttons for it instead of hiding them).
function ButtonTray.CollectsMinimap()
    return ButtonTray.IsEnabled() and Settings()[MINIMAP_KEY] ~= false
end
function ButtonTray.CurrentSet()
    if Settings()[SET_KEY] == "minimap" and ButtonTray.CollectsMinimap() then return "minimap" end
    return "radar"
end
function ButtonTray.IsGathered() return gathered end
function ButtonTray.IsOpen() return gathered and target == 1 end
function ButtonTray.Holds(frame) return adopted[frame] ~= nil end
function ButtonTray.GetSlot() return slot end
function ButtonTray.GetContent() return content end
function ButtonTray.GetHandle() return lip end
function ButtonTray.GetLock() return lock end
function ButtonTray.CellOf(frame) return adopted[frame] and adopted[frame].cell or nil end
function ButtonTray.KindOf(frame) return adopted[frame] and adopted[frame].kind or nil end
function ButtonTray.Side() return slot and slot._side or nil end

-- Grid math (all in the radar's units). Three fixed columns, filled left to
-- right, then the next row.
ButtonTray.COLUMNS, ButtonTray.CELL, ButtonTray.GAP, ButtonTray.PAD = COLUMNS, CELL, GAP, PAD

-- Rows n cells need.
function ButtonTray.Rows(n)
    return ceil(max(0, floor(tonumber(n) or 0)) / COLUMNS)
end

-- Rows the viewport shows: what the radar set needs, at least one, at most
-- what fits under the height cap. Both sets use it, so a flip never resizes.
function ButtonTray.VisibleRows(cap, radarCount)
    local usable = (tonumber(cap) or 0) - 2 * PAD - HEADER - GAP + GAP
    local capRows = max(1, floor(usable / PITCH))
    return max(1, min(capRows, ButtonTray.Rows(radarCount)))
end

-- Content width and height for a viewport of visibleRows rows.
function ButtonTray.Size(visibleRows)
    local rows = max(1, floor(tonumber(visibleRows) or 1))
    return 2 * PAD + GRID_WIDTH, 2 * PAD + HEADER + GAP + rows * PITCH - GAP
end

-- Rows scrolled, kept inside 0..total - visible.
function ButtonTray.ClampScroll(rows, total, visible)
    rows = floor(tonumber(rows) or 0)
    return max(0, min(rows, (tonumber(total) or 0) - (tonumber(visible) or 0)))
end

-- Insertion index (0..n) for a drop at viewport-local x, y (y down from the
-- viewport's top), or nil when the cursor is more than a cell outside. n
-- excludes the dragged cell. The second result is the grid position under
-- the cursor (row * COLUMNS + column, counted from the first row).
function ButtonTray.SlotAt(x, y, n, rows, visibleRows)
    x, y = tonumber(x), tonumber(y)
    n = max(0, floor(tonumber(n) or 0))
    if not (x and y) then return nil end
    local height = max(1, floor(tonumber(visibleRows) or 1)) * PITCH - GAP
    if x < -CELL or x > GRID_WIDTH + CELL or y < -CELL or y > height + CELL then return nil end
    local row = floor((y + (tonumber(rows) or 0) * PITCH) / PITCH)
    row = max(0, min(row, ButtonTray.Rows(n)))
    local column = max(0, min(COLUMNS - 1, floor(x / PITCH)))
    local after = (x - column * PITCH) > CELL / 2
    local position = row * COLUMNS + column
    return min(n, position + (after and 1 or 0)), position
end

-- A button's rank: its index in the saved order, else after every saved
-- name in its default order (Blizzard, then LibDBIcon, then scanned).
function ButtonTray.Rank(saved, name, default)
    default = tonumber(default) or 0
    if type(saved) ~= "table" then return default end
    for index, other in ipairs(saved) do
        if other == name then return index end
    end
    return #saved + default
end

-- The names to save: this session's order, then saved names not here this
-- session in their saved order (a disabled addon keeps its place).
function ButtonTray.MergeOrder(names, saved)
    local merged, seen = {}, {}
    for _, name in ipairs(names or {}) do
        if not seen[name] then seen[name] = true; merged[#merged + 1] = name end
    end
    for _, name in ipairs(type(saved) == "table" and saved or {}) do
        if type(name) == "string" and not seen[name] then seen[name] = true; merged[#merged + 1] = name end
    end
    return merged
end

-- A frame's global name, or nil (other addons' frames are untrusted).
local function GlobalName(frame)
    local ok, name = pcall(function() return frame.GetName and frame:GetName() end)
    if ok and type(name) == "string" and name ~= "" then return name end
    return nil
end

local function Name(frame, fallback)
    return GlobalName(frame) or fallback or "?"
end

-- The stable name a button's place is saved under: the global name for
-- minimap buttons, the tool ID (or "underlay") for radar tools.
local function SaveName(frame, record)
    return record.set == "minimap" and GlobalName(frame) or record.name
end

local function SavedOrder(set)
    local order = Settings()[ORDER_KEY]
    local list = type(order) == "table" and order[set] or nil
    return type(list) == "table" and list or nil
end

local function Write(key, value)
    local schema = addon.Schema
    if schema and schema.Set and schema.Entry and schema.Entry(key) then schema.Set(key, value)
    else Settings()[key] = value end
end

local function Tell(text)
    local say = _G.print
    if type(say) == "function" then say("Magpie: " .. text) end
end

-- Ignore list --------------------------------------------------------------

local function IgnoreList(create)
    local db = Settings()
    local list = db[IGNORE_KEY]
    if type(list) ~= "table" then
        if not create then return nil end
        list = {}
        db[IGNORE_KEY] = list
    end
    return list
end

-- True when a minimap button is on the ignore list, by its global name or
-- the name the tray knows it by (LibDBIcon's name, Blizzard entry name).
function ButtonTray.IsIgnored(frame, name)
    local list = IgnoreList(false)
    if not list then return false end
    local global = frame and GlobalName(frame)
    return global ~= nil and list[global] == true or type(name) == "string" and list[name] == true
end

-- Sorted ignored names.
function ButtonTray.Ignored()
    local names = {}
    for name, value in pairs(IgnoreList(false) or {}) do
        if value == true and type(name) == "string" then names[#names + 1] = name end
    end
    table.sort(names)
    return names
end

function ButtonTray.IsLocked() return Settings()[LOCK_KEY] == true end
function ButtonTray.SetLocked(value)
    Write(LOCK_KEY, value == true)
    Trace("lock %s", value == true and "on" or "off")
end

local function Lib()
    local stub = _G.LibStub
    if type(stub) ~= "table" and type(stub) ~= "function" then return nil end
    local ok, lib = pcall(stub, "LibDBIcon-1.0", true)
    return ok and type(lib) == "table" and lib or nil
end

-- Snapshot and restore -------------------------------------------------------

local function Snapshot(frame, kind)
    local snap = { parent = frame:GetParent(), points = {}, scale = frame:GetScale(),
        strata = frame:GetFrameStrata(), level = frame:GetFrameLevel(),
        alpha = frame.GetAlpha and frame:GetAlpha() or 1, shown = frame:IsShown() == true }
    if frame.IsMouseEnabled then snap.mouse = frame:IsMouseEnabled() end
    for index = 1, (frame.GetNumPoints and frame:GetNumPoints() or 0) do
        snap.points[index] = { frame:GetPoint(index) }
    end
    if kind == "libdbicon" then
        snap.mouseover = frame.showOnMouseover
        snap.border = frame.border and frame.border.IsShown and frame.border:IsShown()
        snap.dragStart = frame:GetScript("OnDragStart")
        snap.dragStop = frame:GetScript("OnDragStop")
    end
    return snap
end

local function SetFixed(frame, value)
    if frame.SetFixedFrameStrata then frame:SetFixedFrameStrata(value) end
    if frame.SetFixedFrameLevel then frame:SetFixedFrameLevel(value) end
end

-- Addon buttons are locked in their cell the way MinimapButtonBag does it:
-- their own move methods become no-ops, so LibDBIcon or another addon moving
-- them does nothing (no hook, no fight). Blizzard frames keep the re-pin hook
-- instead: a no-op called from Blizzard code would spread taint.
local LOCKS = { libdbicon = true, scan = true }
local LOCKED = { "SetPoint", "ClearAllPoints", "SetAllPoints", "SetParent" }
local function NoOp() end

local function LockMethods(frame, record)
    if record.methods then return end
    record.methods = {}
    for _, method in ipairs(LOCKED) do
        record.methods[method] = rawget(frame, method) or false
        frame[method] = NoOp
    end
end

local function UnlockMethods(frame, record)
    if not record.methods then return end
    for _, method in ipairs(LOCKED) do frame[method] = record.methods[method] or nil end
    record.methods = nil
end

local function RestoreFrame(frame, record)
    local snap, kind = record.snap, record.kind
    UnlockMethods(frame, record)
    pinning = true
    local ok, err = pcall(function()
        if kind == "libdbicon" then SetFixed(frame, false) end
        frame:SetParent(snap.parent)
        frame:ClearAllPoints()
        for _, point in ipairs(snap.points) do
            frame:SetPoint(point[1], point[2], point[3], point[4], point[5])
        end
        frame:SetScale(snap.scale)
        frame:SetFrameStrata(snap.strata)
        frame:SetFrameLevel(snap.level)
        if snap.mouse ~= nil and frame.EnableMouse then frame:EnableMouse(snap.mouse) end
        frame:SetShown(snap.shown)
        if kind == "libdbicon" then
            frame:SetScript("OnDragStart", snap.dragStart)
            frame:SetScript("OnDragStop", snap.dragStop)
            if frame.border and snap.border ~= nil then frame.border:SetShown(snap.border) end
            frame.showOnMouseover = snap.mouseover
            -- LibDBIcon re-places it on the Minimap from its own saved spot.
            local lib = Lib()
            if lib and lib.Refresh then pcall(lib.Refresh, lib, record.name) end
            SetFixed(frame, true)
        elseif kind == "radar" then
            frame._vrInTray = nil
        end
        if frame.SetAlpha then frame:SetAlpha(snap.alpha) end
    end)
    pinning = false
    if ok then Trace("restore %s (%s)", record.name, kind)
    else Trace("restore %s failed: %s", record.name, tostring(err)) end
    return ok
end

-- The drawer -----------------------------------------------------------------

local function MarkDirty()
    dirty = true
    if driver and gathered then driver:Show() end
end

-- Cell plates: the theme background lifted toward white, accent on hover.
local function PaintCell(cell)
    local plate = cell and cell.plate
    if not plate then return end
    local style = addon.VignetteRadarStyle
    if cell._hovered and not cell._lifted then
        local r, g, b = .96, .66, .5
        if style and style.Color then r, g, b = style.Color("accent") end
        plate:SetVertexColor(r, g, b, .32)
    else
        local r, g, b = .025, .032, .038
        if style and style.Color then r, g, b = style.Color("background") end
        -- A lifted cell (its button is being moved) dims to show the hole.
        plate:SetVertexColor(r + (1 - r) * .12, g + (1 - g) * .12, b + (1 - b) * .12,
            cell._lifted and LIFTED_PLATE or .8)
    end
end
ButtonTray.PaintCell = PaintCell

-- The drop ring and ghost ring wear the theme's "on" color (IconButton.OnColor),
-- the scroll thumb the rings role, like the other tray surfaces.
local function OnColor()
    local icons = addon.VignetteRadarIconButton
    if icons and icons.OnColor then return icons.OnColor() end
    local style = addon.VignetteRadarStyle
    if style and style.Color then return style.Color("iconHover") end
    return .96, .66, .5
end

local function PaintRings()
    local r, g, b = OnColor()
    if ring and ring.edge then ring.edge:SetVertexColor(r, g, b, .9) end
    if ghost and ghost.edge then ghost.edge:SetVertexColor(r, g, b, .9) end
    if ghost and ghost.plate then
        local style = addon.VignetteRadarStyle
        local pr, pg, pb = .025, .032, .038
        if style and style.Color then pr, pg, pb = style.Color("background") end
        ghost.plate:SetVertexColor(pr + (1 - pr) * .12, pg + (1 - pg) * .12, pb + (1 - pb) * .12, .9)
    end
    if thumb then
        local style = addon.VignetteRadarStyle
        local tr, tg, tb = .45, .52, .54
        if style and style.Color then tr, tg, tb = style.Color("rings") end
        thumb:SetVertexColor(tr, tg, tb, .55)
    end
end

local function Hover(frame, value)
    local record = adopted[frame]
    if not record or record.cell._hovered == value then return end
    record.cell._hovered = value
    PaintCell(record.cell)
end

local function AltDown()
    local alt = _G.IsAltKeyDown
    if type(alt) ~= "function" then return false end
    local ok, value = pcall(alt)
    return ok and value == true
end

local function RePin(frame, why)
    local record = adopted[frame]
    if pinning or not record then return end
    -- Already home: nothing to undo, nothing to trace.
    if frame:GetParent() == record.cell and frame:GetNumPoints() == 1 then
        local point, relative, _, x, y = frame:GetPoint(1)
        if point == "CENTER" and relative == record.cell and x == 0 and y == 0 then return end
    end
    pinning = true
    pcall(function()
        if frame:GetParent() ~= record.cell then frame:SetParent(record.cell) end
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", record.cell, "CENTER", 0, 0)
    end)
    pinning = false
    Trace("re-pin %s after %s", record.name, why or "?")
end

local function HookFrame(frame)
    if hooked[frame] then return end
    hooked[frame] = true
    local hook = _G.hooksecurefunc
    local record = adopted[frame]
    if type(hook) == "function" and not (record and LOCKS[record.kind]) then
        hook(frame, "SetPoint", function(self) if adopted[self] and not pinning then RePin(self, "SetPoint") end end)
        hook(frame, "SetParent", function(self) if adopted[self] and not pinning then RePin(self, "SetParent") end end)
    end
    -- Mail, crafting orders, the compartment and hidden addon buttons come
    -- and go: the grid packs to what is shown.
    if frame.HookScript then
        frame:HookScript("OnShow", function(self) if adopted[self] and not pinning then MarkDirty() end end)
        frame:HookScript("OnHide", function(self) if adopted[self] and not pinning then MarkDirty() end end)
        frame:HookScript("OnEnter", function(self) Hover(self, true) end)
        frame:HookScript("OnLeave", function(self) Hover(self, false) end)
        -- Alt+Right-click puts a gathered minimap button on the ignore list.
        frame:HookScript("OnMouseUp", function(self, button)
            if button == "RightButton" and adopted[self] and AltDown() then ButtonTray.IgnoreFrame(self) end
        end)
    end
end

local function SetFlipIcon()
    if not flip then return end
    local icons = addon.VignetteRadarIconButton
    local showing = ButtonTray.CurrentSet()
    local name = showing == "radar" and (icons and icons.MINIMAP or "minimap") or "radar"
    if icons and icons.HasIcon and not icons.HasIcon(name) then name = "refresh" end
    if flip._icon ~= name and flip.SetIcon then
        flip._icon = name
        flip:SetIcon(name)
    end
end

local function SetOpen(value, why)
    value = value and 1 or 0
    if value == 0 then Cancel("closed") end
    if target == value then return end
    -- Buttons made since the last look join before the tray slides out.
    if value == 1 and ButtonTray.Scan then ButtonTray.Scan("open") end
    from, target, elapsed = progress, value, 0
    Trace("%s (%s)", value == 1 and "open" or "close", why or "?")
    if value == 1 and slot then slot:Show() end
    if lip and lip.SetOpen then lip:SetOpen(value == 1) end
    if driver then driver:Show() end
end

function ButtonTray.SetOpen(value, why) if gathered then SetOpen(value, why) end end
function ButtonTray.Toggle(why) ButtonTray.SetOpen(target ~= 1, why or "lip") end

local function Flip()
    Cancel("flip")
    local nextSet = ButtonTray.CurrentSet() == "radar" and "minimap" or "radar"
    local schema = addon.Schema
    if schema and schema.Set and schema.Entry and schema.Entry(SET_KEY) then schema.Set(SET_KEY, nextSet)
    else Settings()[SET_KEY] = nextSet end
    Trace("flip to %s", nextSet)
    SetFlipIcon()
    MarkDirty()
    ButtonTray.Layout()
end
ButtonTray.Flip = Flip

local function Ensure()
    if content then return end
    slot = CreateFrame("Frame", "VignetteRadarButtonTraySlot", UIParent)
    slot:SetClipsChildren(true)
    slot:Hide()
    content = CreateFrame("Frame", "VignetteRadarButtonTrayFrame", slot)
    content:SetSize(ButtonTray.Size(1))
    content:EnableMouse(true)
    local controls = addon.VignetteRadarControls
    if controls and controls.RoundedStatusSurface then controls.RoundedStatusSurface(content) end
    -- The grid scrolls inside a clipped viewport by moving the group's anchor
    -- (no cell is hidden for it: hiding one would hide the button inside).
    viewport = CreateFrame("Frame", nil, content)
    viewport:SetClipsChildren(true)
    viewport:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, -(PAD + HEADER + GAP))
    viewport:SetSize(GRID_WIDTH, CELL)
    viewport:EnableMouseWheel(true)
    viewport:SetScript("OnMouseWheel", function(_, delta) ButtonTray.Scroll(-(tonumber(delta) or 0)) end)
    groups = {}
    for _, set in ipairs({ "radar", "minimap" }) do
        local group = CreateFrame("Frame", nil, viewport)
        group:SetPoint("TOPLEFT", viewport, "TOPLEFT", 0, 0)
        group:SetSize(GRID_WIDTH, CELL)
        group:Hide()
        groups[set] = group
    end
    -- Drop ring: marks the gap a dragged button would land in.
    ring = CreateFrame("Frame", nil, viewport)
    ring:SetSize(CELL + 2, CELL + 2)
    ring:SetFrameLevel(content:GetFrameLevel() + 8)
    ring.edge = ring:CreateTexture(nil, "OVERLAY")
    ring.edge:SetAllPoints(ring)
    local layers = addon.VignetteRadarIconButton
    if layers and layers.ATLAS and layers.LayerCoords then
        ring.edge:SetTexture(layers.ATLAS)
        ring.edge:SetTexCoord(layers.LayerCoords("border"))
    else
        ring.edge:SetTexture(PLATE_TEXTURE)
    end
    ring:Hide()
    thumb = content:CreateTexture(nil, "ARTWORK")
    thumb:SetColorTexture(1, 1, 1, 1)
    thumb:SetWidth(THUMB)
    thumb:Hide()
    PaintRings()
    local icons = addon.VignetteRadarIconButton
    if icons and icons.Create then
        flip = icons.Create(content, icons.MINIMAP or "minimap", {
            size = FLIP_SIZE, label = "Flip Tray",
            tooltip = function()
                return ButtonTray.CurrentSet() == "radar"
                    and "Showing radar buttons. Click to show minimap buttons."
                    or "Showing minimap buttons. Click to show radar buttons."
            end,
            onClick = function() Flip() end,
        })
        flip:SetPoint("TOPLEFT", content, "TOPLEFT", PAD + CELL + GAP, -PAD)
        flip:SetFrameLevel(content:GetFrameLevel() + 6)
    end
    local tray = addon.VignetteRadarTray
    if icons and icons.Create and tray and tray.CreateLockButton then
        -- The tray's own lock: keeps it out through clicks elsewhere and combat.
        lock = tray.CreateLockButton(content, {
            size = FLIP_SIZE, isLocked = ButtonTray.IsLocked, setLocked = ButtonTray.SetLocked,
            labels = { "Tray Unlocked", "Tray Locked" },
        })
        lock:SetFrameLevel(content:GetFrameLevel() + 6)
    end
    emptyText = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    local style = addon.VignetteRadarStyle
    if style and style.SetFont then style.SetFont(emptyText, 10, "") end
    emptyText:SetText("No Buttons")
    emptyText:SetPoint("TOP", viewport, "TOP", 0, -4)
    emptyText:Hide()
    if tray and tray.RegisterToggle then tray.RegisterToggle(slot) end
    content:SetScript("OnShow", function()
        if tray and tray.SkinLikeRadar then tray.SkinLikeRadar(content) end
        if flip and flip.Refresh then flip:Refresh() end
        if lock and lock.RefreshLock then lock:RefreshLock() end
    end)
end

local function EnsureLip(host)
    local tray = addon.VignetteRadarTray
    if lip then
        if lip:GetParent() ~= host then lip:SetParent(host) end
        return lip
    end
    if not (tray and tray.CreateHandle) then return nil end
    lip = tray.CreateHandle(host, {
        levelOffset = 31, iconColumn = 0,
        onClick = function() ButtonTray.Toggle("lip") end,
        onEnter = function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, self.side == "left" and "ANCHOR_LEFT" or "ANCHOR_RIGHT")
            GameTooltip:SetText("Button Tray", 1, .87, .66)
            GameTooltip:AddLine(ButtonTray.CurrentSet() == "radar" and "Radar Buttons" or "Minimap Buttons",
                .66, .8, .78, true)
            GameTooltip:AddLine(target == 1 and "Click To Slide The Tray In." or "Click To Slide The Tray Out.",
                .66, .8, .78, true)
            GameTooltip:AddLine("Press And Hold A Button To Move It.", .66, .8, .78, true)
            GameTooltip:Show()
        end,
        onLeave = function() if GameTooltip then GameTooltip:Hide() end end,
    })
    if tray.RegisterToggle then tray.RegisterToggle(lip) end
    return lip
end

local function HideDrawer()
    if slot then slot:Hide() end
    if lip then lip:Hide() end
end

-- The radar's scale relative to UIParent: the tray wears it, so gathered
-- buttons keep the size they had on the face.
local function HostScale(host)
    local own = host and host.GetEffectiveScale and host:GetEffectiveScale()
    local base = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()
    if type(own) == "number" and type(base) == "number" and own > 0 and base > 0 then return own / base end
    return 1
end

-- Picks the side away from the radar tray, then the side with room, and the
-- shrink (MIN_FIT..1) that keeps the drawer on screen.
local function ChooseSide(face, host, width)
    local tray = addon.VignetteRadarTray
    local main = tray and tray.Side and tray.Side() or nil
    local prefer = main == "right" and "left" or "right"
    local rect = tray and tray.Rect
    local left, right = nil, nil
    if rect then left, right = rect(face, host) end
    local screen = UIParent and UIParent.GetWidth and UIParent:GetWidth()
    if not (left and right and type(screen) == "number" and screen > 0) then return prefer, 1 end
    local need = max(1, width * HostScale(host))
    local room = { right = screen - MARGIN - right, left = left - MARGIN }
    local side = prefer
    local other = OPPOSITE[prefer]
    if room[side] < need and other ~= main and room[other] > room[side] then side = other end
    local fit = max(MIN_FIT, min(1, room[side] / need))
    return side, floor(fit * 1000) / 1000
end

-- Lays the slot, content and lip out for the current slide progress.
function ButtonTray.Place()
    if not (gathered and content) then HideDrawer(); return false end
    local tray = addon.VignetteRadarTray
    local face, host = nil, nil
    if tray and tray.Face then face, host = tray.Face() end
    if not face then HideDrawer(); return false end
    local width, height = content:GetWidth(), content:GetHeight()
    local side, fit = ChooseSide(face, host, width)
    local scale = HostScale(host)
    local k = scale * fit
    local top, join = tray.TOP_OFFSET or 10, tray.JOIN or 5
    local below = tray.STRATA_BELOW and tray.STRATA_BELOW[host:GetFrameStrata()] or "LOW"
    if slot._side ~= side or slot._k ~= k or slot._face ~= face or slot._width ~= width
        or slot._height ~= height or slot._strata ~= below then
        local moved = slot._side ~= side
        slot._side, slot._k, slot._face, slot._width, slot._height = side, k, face, width, height
        slot:SetFrameStrata(below)
        slot:SetSize(width * k, height * k)
        slot:ClearAllPoints()
        if side == "right" then slot:SetPoint("TOPLEFT", face, "TOPRIGHT", -join, -top)
        else slot:SetPoint("TOPRIGHT", face, "TOPLEFT", join, -top) end
        content:SetScale(k)
        if slot._strata ~= below then
            slot._strata = below
            content:SetFrameStrata(below)
            pinning = true
            for frame in pairs(adopted) do pcall(frame.SetFrameStrata, frame, below) end
            pinning = false
        end
        slot._retreat = nil
        if moved and tray.SquareJoin then tray.SquareJoin(content, side) end
    end
    local retreat = floor(width * (1 - progress) * 10 + .5) / 10
    if slot._retreat ~= retreat then
        slot._retreat = retreat
        content:ClearAllPoints()
        if side == "right" then content:SetPoint("TOPLEFT", slot, "TOPLEFT", -retreat, 0)
        else content:SetPoint("TOPRIGHT", slot, "TOPRIGHT", retreat, 0) end
    end
    local handle = EnsureLip(host)
    if handle and scale > 0 then
        handle:PlaceOn(face, side, height * k / scale, top / scale)
        handle:SetOpen(target == 1)
    end
    slot:SetShown(progress > 0 or target > 0)
    return true
end

-- Shown records of one set in tray order (the pinned config tool apart),
-- after applying the Advanced Tools rule to radar tools.
local function Collect(set, advanced)
    local shown, pinned = {}, nil
    for _, frame in ipairs(lists[set]) do
        local record = adopted[frame]
        if record then
            if record.kind == "radar" then
                -- Advanced Tools corners stay hidden while off, as on the face.
                local want = advanced or not frame.advancedTool
                if frame:IsShown() ~= want then
                    pinning = true
                    frame:SetShown(want)
                    pinning = false
                end
            end
            local visible = frame:IsShown() == true
            record.cell:SetShown(visible)
            if visible and record.pinned then pinned = record
            elseif visible then shown[#shown + 1] = record end
        end
    end
    return shown, pinned
end

-- Puts a cell at grid position (0-based, row-major) in its set's group.
local function PlaceCell(record, group, position)
    local cell = record.cell
    if cell:GetParent() ~= group then cell:SetParent(group) end
    cell:ClearAllPoints()
    cell:SetPoint("TOPLEFT", group, "TOPLEFT", (position % COLUMNS) * PITCH, -floor(position / COLUMNS) * PITCH)
end

-- Anchors the shown set's group for its scroll and moves the thumb.
local function AnchorGroup()
    local set = current.set
    local group = set and groups[set]
    if not group then return end
    local rows = scrollRows[set] or 0
    group:ClearAllPoints()
    group:SetPoint("TOPLEFT", viewport, "TOPLEFT", 0, rows * PITCH)
    group:SetSize(GRID_WIDTH, max(1, current.total) * PITCH)
    local total, visible = current.total, current.visible
    if total > visible then
        local height = visible * PITCH - GAP
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPLEFT", viewport, "TOPRIGHT", (PAD - THUMB) / 2, -height * rows / total)
        thumb:SetHeight(max(4, height * visible / total))
        thumb:Show()
    else
        thumb:Hide()
    end
end

-- Scrolls the shown set by step rows (wheel: one row per notch, like the
-- Quest Tracker). Returns true when it moved.
function ButtonTray.Scroll(step)
    local set = current.set
    if not (set and viewport) then return false end
    local rows = ButtonTray.ClampScroll((scrollRows[set] or 0) + (tonumber(step) or 0), current.total, current.visible)
    if rows == scrollRows[set] then return false end
    scrollRows[set] = rows
    AnchorGroup()
    return true
end

-- Places the cells of the shown set and sizes the content.
function ButtonTray.Layout()
    dirty = false
    if not (gathered and content) then return end
    local set = ButtonTray.CurrentSet()
    local advanced = Settings().vignetteRadarAdvancedTools == true
    for name, group in pairs(groups) do group:SetShown(name == set) end
    local radarShown, pinned = Collect("radar", advanced)
    local shown = radarShown
    if set ~= "radar" then shown = Collect("minimap", advanced) end
    -- Mid-drag: lay out the preview (the others shifted around the gap), so a
    -- button joining or leaving does not snap the grid back.
    local gap = nil
    if drag and drag.state == "dragging" then
        local order, found = {}, false
        if drag.set == set and adopted[drag.frame] == drag.record then
            for _, record in ipairs(shown) do
                if record == drag.record then found = true else order[#order + 1] = record end
            end
        end
        if not found then
            Cancel("button left")
            return
        end
        shown, drag.order = order, order
        drag.origin = min(drag.origin, #order)
        if drag.slot then drag.slot = min(drag.slot, #order) end
        gap = drag.slot or drag.origin
    else
        current.shown = shown
    end
    local tray = addon.VignetteRadarTray
    local face = tray and tray.Face and tray.Face()
    local faceHeight = face and face.GetHeight and face:GetHeight() or 0
    local _, minHeight = ButtonTray.Size(1)
    local cap = max(minHeight, (faceHeight or 0) - 2 * (tray and tray.TOP_OFFSET or 10))
    local visible = ButtonTray.VisibleRows(cap, #radarShown)
    local total = ButtonTray.Rows(#shown + (gap and 1 or 0))
    current.set, current.total, current.visible = set, total, visible
    scrollRows[set] = ButtonTray.ClampScroll(scrollRows[set] or 0, total, visible)
    local group = groups[set]
    local position = 0
    for _, record in ipairs(shown) do
        if position == gap then position = position + 1 end
        PlaceCell(record, group, position)
        position = position + 1
    end
    if gap then
        -- The lifted button waits, dimmed, in the gap it would drop into.
        PlaceCell(drag.record, group, gap)
        ring:ClearAllPoints()
        ring:SetPoint("CENTER", drag.record.cell, "CENTER", 0, 0)
    end
    ring:SetShown(gap ~= nil and drag.slot ~= nil)
    local headerX = PAD
    if pinned then
        -- The config tool sits in the header, outside the scroll, in both sets.
        local cell = pinned.cell
        if cell:GetParent() ~= content then cell:SetParent(content) end
        cell:ClearAllPoints()
        cell:SetPoint("TOPLEFT", content, "TOPLEFT", PAD, -PAD)
        headerX = PAD + CELL + GAP
    end
    local width, height = ButtonTray.Size(visible)
    local empty = #shown == 0 and not gap
    emptyText:SetShown(empty)
    if empty then
        -- Never cut the note: the tray widens to its measured width if needed.
        local measured = emptyText.GetUnboundedStringWidth and emptyText:GetUnboundedStringWidth() or 60
        width = max(width, ceil(measured) + 2 * PAD + 3)
    end
    viewport:SetSize(GRID_WIDTH, visible * PITCH - GAP)
    AnchorGroup()
    if flip then flip:SetShown(ButtonTray.CollectsMinimap()) end
    SetFlipIcon()
    -- Header: config (pinned), then the flip (when shown) and the lock.
    local header = {}
    if flip and flip:IsShown() then header[#header + 1] = flip end
    if lock then header[#header + 1] = lock end
    for index, button in ipairs(header) do
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", content, "TOPLEFT", headerX + (index - 1) * (FLIP_SIZE + GAP),
            -(PAD + (HEADER - FLIP_SIZE) / 2))
    end
    width = max(width, headerX + #header * (FLIP_SIZE + GAP) - GAP + PAD)
    content:SetSize(width, height)
    ButtonTray.Place()
end

-- Gather and give back -------------------------------------------------------

local function Insert(list, frame, order)
    for index, other in ipairs(list) do
        local record = adopted[other]
        if record and record.order > order then
            table.insert(list, index, frame)
            return
        end
    end
    list[#list + 1] = frame
end

-- A cell for one gathered frame, with its rounded plate; reused per set.
local function TakeCell(set)
    local pool = spare[set]
    local cell = pool[#pool]
    if cell then
        pool[#pool] = nil
        -- A pinned (header) cell came back parented to the content.
        if cell:GetParent() ~= groups[set] then cell:SetParent(groups[set]) end
    else
        cell = CreateFrame("Frame", nil, groups[set])
        cell:SetSize(CELL, CELL)
        cell.plate = cell:CreateTexture(nil, "BACKGROUND")
        cell.plate:SetTexture(PLATE_TEXTURE)
        cell.plate:SetAllPoints(cell)
    end
    cell._hovered = false
    PaintCell(cell)
    cell:Show()
    return cell
end

local function GiveCell(set, cell)
    cell:Hide()
    cell:ClearAllPoints()
    cell._hovered, cell._lifted = false, false
    if cell.SetAlpha then cell:SetAlpha(1) end
    local pool = spare[set]
    pool[#pool + 1] = cell
end

local function Adopt(frame, kind, set, name, order)
    if not frame or adopted[frame] or type(frame.SetParent) ~= "function" then return false end
    if set == "minimap" and ButtonTray.IsIgnored(frame, name) then
        if skipped[frame] ~= "ignored" then
            skipped[frame] = "ignored"
            Trace("skip %s (ignored)", name)
        end
        return false
    end
    if Protected(frame) and Locked() then
        queued[frame] = { kind = kind, set = set, name = name, order = order }
        Trace("gather %s waits for combat to end", name)
        return false
    end
    Ensure()
    -- order is the default place; the saved order (by stable name) wins.
    local record = { kind = kind, set = set, name = name, default = order, snap = Snapshot(frame, kind),
        frame = frame, pinned = kind == "radar" and name == PINNED or nil }
    order = ButtonTray.Rank(SavedOrder(set), SaveName(frame, record), order)
    record.order = order
    local cell = TakeCell(set)
    record.cell = cell
    local width, height = frame:GetWidth() or 0, frame:GetHeight() or 0
    local size = max(width, height)
    local scale = size > 0 and min(1, CELL / size) or 1
    adopted[frame] = record
    pinning = true
    local ok, err = pcall(function()
        if kind == "libdbicon" then
            SetFixed(frame, false)
            frame:SetScript("OnDragStart", nil)
            frame:SetScript("OnDragStop", nil)
            frame.showOnMouseover = false
            if frame.fadeOut and frame.fadeOut.Stop then frame.fadeOut:Stop() end
            if frame.border and frame.border.Hide then frame.border:Hide() end
        end
        frame:SetParent(cell)
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", cell, "CENTER", 0, 0)
        frame:SetScale(scale)
        frame:SetFrameStrata(slot._strata or content:GetFrameStrata())
        frame:SetFrameLevel(content:GetFrameLevel() + 4)
        if frame.SetAlpha then frame:SetAlpha(1) end
        if kind == "radar" then
            frame._vrInTray = true
            frame:Show()
        elseif kind == "libdbicon" then
            frame:SetShown(not (frame.db and frame.db.hide))
        elseif name == "ExpansionLandingPageMinimapButton" and frame.EnableMouse then
            -- The underlay turns its mouse off with the chrome; in the tray it is clickable.
            frame:EnableMouse(true)
        end
        if LOCKS[kind] then LockMethods(frame, record) end
    end)
    pinning = false
    if not ok then
        adopted[frame] = nil
        RestoreFrame(frame, record)
        GiveCell(set, cell)
        Trace("gather %s failed: %s", name, tostring(err))
        return false
    end
    HookFrame(frame)
    Insert(lists[set], frame, order)
    Trace("gather %s (%s) into %s, scale %.2f", name, kind, set, scale)
    MarkDirty()
    return true
end

local function Remove(list, frame)
    for index = #list, 1, -1 do
        if list[index] == frame then table.remove(list, index) end
    end
end

-- Gives one frame back; protected frames wait for combat to end.
local function Release(frame)
    local record = adopted[frame]
    if not record then return true end
    if drag and drag.frame == frame then Cancel("button given back") end
    if Protected(frame) and Locked() then
        retry = true
        Trace("restore %s waits for combat to end", record.name)
        return false
    end
    adopted[frame] = nil
    Remove(lists[record.set], frame)
    RestoreFrame(frame, record)
    GiveCell(record.set, record.cell)
    MarkDirty()
    return true
end

-- Gives back every minimap-set frame (and queued one) the test picks.
local function ReleaseWhere(test)
    local list = lists.minimap
    for index = #list, 1, -1 do
        local frame = list[index]
        local record = adopted[frame]
        if record and test(frame, record) then Release(frame) end
    end
    for frame, entry in pairs(queued) do
        if entry.set == "minimap" and test(frame, entry) then queued[frame] = nil end
    end
end

-- The radar re-applies its own corner-tool visibility on its next render.
local function ResetRadarChrome()
    local panel = panelRef
    if not panel then
        local radar = addon.VignetteRadarAPI
        panel = radar and radar.GetPanel and radar.GetPanel()
    end
    if not panel then return end
    panel._hoverToolsVisible, panel._chromeTools = nil, nil
    -- The underlay toggle follows the "Stay Fully Visible" tool, as on the face.
    local underlay = addon.VignetteRadarMinimapUnderlay
    local tool = underlay and underlay.GetTool and underlay.GetTool()
    if tool and not adopted[tool] then
        for _, other in ipairs(panel.hoverTools or {}) do
            if other.toolID == "eye" then tool:SetShown(other:IsShown()); break end
        end
    end
    if panel.RefreshCornerTools then pcall(panel.RefreshCornerTools) end
end

local function ReleaseSet(set)
    local list = lists[set]
    for index = #list, 1, -1 do Release(list[index]) end
    for frame, entry in pairs(queued) do
        if entry.set == set then queued[frame] = nil end
    end
    if set == "radar" then ResetRadarChrome() end
end

local function GatherRadar(panel)
    if not (panel and panel.hoverTools) then return end
    for index, tool in ipairs(panel.hoverTools) do
        Adopt(tool, "radar", "radar", tool.toolID or ("tool" .. index), index)
    end
    local underlay = addon.VignetteRadarMinimapUnderlay
    local tool = underlay and underlay.GetTool and underlay.GetTool()
    if tool then Adopt(tool, "radar", "radar", "underlay", 100) end
end

local function AdoptLibButton(button, name, order)
    if type(name) ~= "string" then name = Name(button, "LibDBIcon") end
    Adopt(button, "libdbicon", "minimap", name, order)
end

-- True while Edit Mode is open: Blizzard's frames stay with Blizzard.
local function Editing()
    if editing then return true end
    local manager = _G.EditModeManagerFrame
    if not (manager and type(manager.IsEditModeActive) == "function") then return false end
    local ok, active = pcall(manager.IsEditModeActive, manager)
    return ok and active == true
end
ButtonTray.Editing = Editing

-- Why the fallback scan leaves a frame alone, or nil to gather it.
function ButtonTray.ScanReason(frame)
    if type(frame) ~= "table" then return "not a frame" end
    if adopted[frame] then return "gathered" end
    local okType, kind = pcall(function() return frame.GetObjectType and frame:GetObjectType() end)
    if not okType or kind ~= "Button" then return "not a button" end
    local name = GlobalName(frame)
    if not name then return "no name" end
    if name:find("^LibDBIcon10_") then return "LibDBIcon" end
    if name:find("^VignetteRadar") then return "ours" end
    if NOT_ADDON[name] or frame == _G.HybridMinimap then return "Blizzard" end
    for _, entry in ipairs(BLIZZARD) do
        if entry.get() == frame then return "Blizzard" end
    end
    if ButtonTray.IsIgnored(frame, name) then return "ignored" end
    local okSize, width, height = pcall(function() return frame:GetWidth(), frame:GetHeight() end)
    if not (okSize and type(width) == "number" and type(height) == "number") then return "no size" end
    if width < SCAN_MIN or height < SCAN_MIN or width > SCAN_MAX or height > SCAN_MAX
        or max(width, height) > SCAN_RATIO * min(width, height) then
        return ("size %dx%d"):format(floor(width + .5), floor(height + .5))
    end
    if frame.IsMouseEnabled then
        local okMouse, mouse = pcall(frame.IsMouseEnabled, frame)
        if okMouse and mouse == false then return "no mouse" end
    end
    return nil
end

local function Children(frame)
    if not (frame and frame.GetChildren) then return {} end
    local ok, list = pcall(function() return { frame:GetChildren() } end)
    return ok and list or {}
end

-- Gathers hand-made minimap buttons; returns how many joined.
function ButtonTray.Scan(why)
    scanWait = nil
    if not (gathered and ButtonTray.CollectsMinimap() and Settings()[SCAN_KEY] ~= false) then return 0 end
    local found, seen = {}, {}
    local function Visit(frame)
        if seen[frame] then return end
        seen[frame] = true
        local reason = ButtonTray.ScanReason(frame)
        if reason == nil then
            found[#found + 1] = { frame = frame, name = GlobalName(frame) }
        elseif reason ~= "gathered" and reason ~= "no name" and reason ~= "not a button"
            and skipped[frame] ~= reason then
            -- Each named skip is traced once per reason.
            skipped[frame] = reason
            Trace("skip %s (%s)", Name(frame), reason)
        end
    end
    for _, root in ipairs({ _G.Minimap, _G.MinimapCluster }) do
        for _, child in ipairs(Children(root)) do
            Visit(child)
            for _, grandchild in ipairs(Children(child)) do Visit(grandchild) end
        end
    end
    table.sort(found, function(a, b) return a.name < b.name end)
    local joined = 0
    for index, entry in ipairs(found) do
        if Adopt(entry.frame, "scan", "minimap", entry.name, 300 + index) then joined = joined + 1 end
    end
    if joined > 0 then Trace("scan (%s): %d joined", why or "?", joined) end
    return joined
end

local function GatherMinimap()
    local editMode = Editing()
    for index, entry in ipairs(BLIZZARD) do
        local frame = not editMode and entry.get()
        if frame then Adopt(frame, "blizzard", "minimap", entry.name, index) end
    end
    local lib = Lib()
    if not lib then ButtonTray.Scan("gather"); return end
    if not libHooked and type(lib.RegisterCallback) == "function" then
        libHooked = true
        -- Buttons created later (addons that load on demand) join the tray.
        pcall(lib.RegisterCallback, ButtonTray, "LibDBIcon_IconCreated", function(_, button, name)
            if gathered and ButtonTray.CollectsMinimap() then
                AdoptLibButton(button, name, 200)
                ButtonTray.Layout()
            end
        end)
    end
    local names = {}
    if type(lib.GetButtonList) == "function" then
        local ok, list = pcall(lib.GetButtonList, lib)
        if ok and type(list) == "table" then
            for _, name in ipairs(list) do if type(name) == "string" then names[#names + 1] = name end end
        end
    end
    table.sort(names)
    for index, name in ipairs(names) do
        local ok, button = pcall(lib.GetMinimapButton, lib, name)
        if ok and button then AdoptLibButton(button, name, 100 + index) end
    end
    ButtonTray.Scan("gather")
end

-- Minimap-set frames that must go back now: ignored, scanned with the scan
-- off, or Blizzard's while Edit Mode is open.
local function LetGo(frame, record)
    if ButtonTray.IsIgnored(frame, record.name) then return true end
    if record.kind == "scan" and Settings()[SCAN_KEY] == false then return true end
    return record.kind == "blizzard" and Editing()
end

-- Brings the tray in line with the underlay and the settings.
function ButtonTray.Sync()
    Cancel("sync")
    local want = underlayOn and ButtonTray.IsEnabled()
    if not want then
        ReleaseSet("minimap")
        ReleaseSet("radar")
        local left = next(adopted) ~= nil
        if gathered and not left then Trace("tray put away") end
        gathered = left
        if not left then
            progress, target, from, elapsed = 0, 0, 0, 0
            HideDrawer()
            if driver then driver:Hide() end
        end
        return
    end
    Ensure()
    gathered = true
    GatherRadar(panelRef)
    if ButtonTray.CollectsMinimap() then
        ReleaseWhere(LetGo)
        GatherMinimap()
    else
        ReleaseSet("minimap")
    end
    if driver then driver:Show() end
    ButtonTray.Layout()
end

-- Called by UI/MinimapUnderlay.lua right after a borrow (true) and during a
-- give-back (false), both out of combat.
function ButtonTray.OnUnderlay(on, panel)
    underlayOn = on == true
    if panel then panelRef = panel end
    ButtonTray.Sync()
end

-- Settings changed (Schema onChange).
function ButtonTray.Refresh()
    local underlay = addon.VignetteRadarMinimapUnderlay
    underlayOn = underlay and underlay.IsActive and underlay.IsActive() == true or false
    if not panelRef then
        local radar = addon.VignetteRadarAPI
        panelRef = radar and radar.GetPanel and radar.GetPanel()
    end
    ButtonTray.Sync()
end

-- Edit Mode: Blizzard's frames go back while it is open (it re-anchors the
-- cluster's pieces), and are gathered again when it closes.
function ButtonTray.OnEditMode(active)
    editing = active == true
    Trace("edit mode %s: Blizzard buttons %s", editing and "on" or "off", editing and "given back" or "gathered")
    if gathered then ButtonTray.Sync() end
end

do
    local registry = _G.EventRegistry
    if type(registry) == "table" and type(registry.RegisterCallback) == "function" then
        pcall(registry.RegisterCallback, registry, "EditMode.Enter", function() ButtonTray.OnEditMode(true) end,
            ButtonTray)
        pcall(registry.RegisterCallback, registry, "EditMode.Exit", function() ButtonTray.OnEditMode(false) end,
            ButtonTray)
    end
end

-- Ignore list and /magpie buttons ---------------------------------------------

function ButtonTray.Ignore(name)
    if type(name) ~= "string" or name == "" then return false end
    IgnoreList(true)[name] = true
    Trace("ignore %s", name)
    if gathered then ButtonTray.Sync() end
    return true
end

-- Removes a name (exact, else the one match ignoring case); returns the
-- name removed or nil.
function ButtonTray.Unignore(name)
    local list = IgnoreList(false)
    if not (list and type(name) == "string") then return nil end
    local key = list[name] and name or nil
    if not key then
        for other in pairs(list) do
            if type(other) == "string" and other:lower() == name:lower() then key = other; break end
        end
    end
    if not key then return nil end
    list[key] = nil
    Trace("unignore %s", key)
    if gathered then ButtonTray.Sync() end
    return key
end

function ButtonTray.ResetIgnore()
    local count = #ButtonTray.Ignored()
    Settings()[IGNORE_KEY] = {}
    Trace("ignore list cleared (%d)", count)
    if gathered then ButtonTray.Sync() end
    return count
end

-- Alt+Right-click in the tray: ignore that minimap button and give it back.
function ButtonTray.IgnoreFrame(frame)
    local record = adopted[frame]
    if not (record and record.set == "minimap") then return false end
    local name = GlobalName(frame) or record.name
    ButtonTray.Ignore(name)
    Tell(("%s is ignored and back on the minimap. Type /magpie buttons unignore %s to gather it again."):format(
        name, name))
    return true
end

-- Names in the tray for one set, in tray order.
function ButtonTray.Gathered(set)
    local names = {}
    for _, frame in ipairs(lists[set] or {}) do
        local record = adopted[frame]
        if record then names[#names + 1] = record.set == "minimap" and GlobalName(frame) or record.name end
    end
    return names
end

local function Joined(names) return #names > 0 and table.concat(names, ", ") or "none" end

-- Saved order ----------------------------------------------------------------

local function CopyOrder()
    local saved, copy = Settings()[ORDER_KEY], {}
    for _, set in ipairs({ "radar", "minimap" }) do
        local list = type(saved) == "table" and saved[set] or nil
        copy[set] = {}
        for index, name in ipairs(type(list) == "table" and list or {}) do copy[set][index] = name end
    end
    return copy
end

-- Saves one set's tray order (the pinned tool apart), keeping saved names
-- that are not here this session at the tail.
function ButtonTray.SaveOrder(set)
    local names = {}
    for _, frame in ipairs(lists[set] or {}) do
        local record = adopted[frame]
        if record and not record.pinned then names[#names + 1] = SaveName(frame, record) end
    end
    local order = CopyOrder()
    order[set] = ButtonTray.MergeOrder(names, order[set])
    Write(ORDER_KEY, order)
    Trace("order %s saved (%d)", set, #order[set])
end

-- Re-ranks every gathered button from the saved order (after a reset or a
-- profile change) and lays the tray out again.
function ButtonTray.ApplyOrder()
    Cancel("order changed")
    for set, list in pairs(lists) do
        local saved, position = SavedOrder(set), {}
        for index, frame in ipairs(list) do
            position[frame] = index
            local record = adopted[frame]
            if record then record.order = ButtonTray.Rank(saved, SaveName(frame, record), record.default) end
        end
        table.sort(list, function(a, b)
            local ra, rb = adopted[a], adopted[b]
            local oa, ob = ra and ra.order or 0, rb and rb.order or 0
            if oa ~= ob then return oa < ob end
            return position[a] < position[b]
        end)
    end
    if gathered then ButtonTray.Layout() end
end

-- Clears the saved order of one set (or both); returns the names cleared.
function ButtonTray.ResetOrder(set)
    local order, count = CopyOrder(), 0
    for _, name in ipairs({ "radar", "minimap" }) do
        if set == nil or set == name then
            count = count + #order[name]
            order[name] = {}
        end
    end
    Write(ORDER_KEY, order)
    Trace("order reset (%s, %d)", set or "both", count)
    ButtonTray.ApplyOrder()
    return count
end

-- /magpie buttons [list | reset | ignore <name> | unignore <name> |
-- order [reset [radar | minimap]]]; names keep their case.
function ButtonTray.Command(rest)
    local word, arg = tostring(rest or ""):match("^%s*(%S*)%s*(.-)%s*$")
    word = (word or ""):lower()
    if word == "" or word == "list" then
        if gathered then
            local minimap, radar = ButtonTray.Gathered("minimap"), ButtonTray.Gathered("radar")
            Tell(("Minimap buttons in the tray (%d): %s"):format(#minimap, Joined(minimap)))
            Tell(("Radar buttons in the tray (%d): %s"):format(#radar, Joined(radar)))
        else
            Tell("The Button Tray is put away (it gathers while the Minimap Underlay is on).")
        end
        local ignored = ButtonTray.Ignored()
        Tell(("Ignored (%d): %s"):format(#ignored, Joined(ignored)))
        Tell("Alt+Right-click a minimap button in the tray to ignore it. /magpie buttons unignore <name> undoes it.")
    elseif word == "reset" then
        Tell(("Ignore list cleared (%d removed)."):format(ButtonTray.ResetIgnore()))
    elseif word == "ignore" and arg ~= "" then
        ButtonTray.Ignore(arg)
        Tell(("%s is ignored. Type /magpie buttons unignore %s to undo."):format(arg, arg))
    elseif word == "unignore" and arg ~= "" then
        local removed = ButtonTray.Unignore(arg)
        Tell(removed and (removed .. " is no longer ignored.") or (arg .. " is not on the ignore list."))
    elseif word == "order" and (arg == "" or arg:lower() == "list") then
        for _, set in ipairs({ "radar", "minimap" }) do
            local saved = SavedOrder(set) or {}
            Tell(("Saved %s order (%d): %s"):format(set, #saved, Joined(saved)))
        end
        Tell("Press and hold a button in the tray, then drag it to move it. /magpie buttons order reset"
            .. " [radar | minimap] puts the default order back.")
    elseif word == "order" and arg:lower():match("^reset") then
        local which = arg:lower():match("^reset%s*(%S*)$")
        if which == "" or which == "radar" or which == "minimap" then
            local count = ButtonTray.ResetOrder(which ~= "" and which or nil)
            Tell(("Button order reset for %s (%d names cleared)."):format(
                which ~= "" and (which .. " buttons") or "both sets", count))
        else
            Tell("Usage: /magpie buttons order reset [radar | minimap]")
        end
    else
        Tell("Usage: /magpie buttons [list | reset | ignore <name> | unignore <name> | order [reset [radar | minimap]]]")
    end
end

-- Adds "buttons" to /vr from this later-loading file (UI/Radar.lua's handler
-- lowercases input and is near the local limit).
local function InstallSlash()
    local slash = _G.SlashCmdList
    if type(slash) ~= "table" or type(slash.VIGNETTERADAR) ~= "function" or ButtonTray.slashInstalled then return end
    ButtonTray.slashInstalled = true
    local original = slash.VIGNETTERADAR
    slash.VIGNETTERADAR = function(message)
        local word, rest = tostring(message or ""):match("^%s*(%S*)%s*(.-)%s*$")
        if (word or ""):lower() == "buttons" then return ButtonTray.Command(rest) end
        return original(message)
    end
end
ButtonTray.InstallSlash = InstallSlash
InstallSlash()
if addon.Bus and addon.Bus.On then addon.Bus.On("LOGIN", InstallSlash) end

-- Press-and-hold reorder -------------------------------------------------------
-- No script on a gathered button is replaced and no click is forwarded: a
-- press is watched through GLOBAL_MOUSE_DOWN + GetMouseFoci, a quick click
-- stays the button's own, and a pickup puts a mouse-enabled ghost under the
-- cursor so the release lands on it (no OnClick on the button).

ButtonTray.DRAG_PX, ButtonTray.HOLD_SECONDS = DRAG_PX, HOLD_SECONDS

local function UIScale()
    local scale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()
    return type(scale) == "number" and scale > 0 and scale or 1
end

local function Effective(frame)
    local scale = frame and frame.GetEffectiveScale and frame:GetEffectiveScale()
    return type(scale) == "number" and scale > 0 and scale or 1
end

-- Cursor (screen pixels) to viewport-local units: x from the left edge, y
-- down from the top edge. nil while the viewport has no rect.
local function Local(x, y)
    if not viewport then return nil end
    local left, top = viewport:GetLeft(), viewport:GetTop()
    if type(left) ~= "number" or type(top) ~= "number" then return nil end
    local scale = Effective(viewport)
    return x / scale - left, top - y / scale
end

local function MouseDown()
    local down = _G.IsMouseButtonDown
    if type(down) ~= "function" then return true end
    local ok, value = pcall(down, "LeftButton")
    return not ok or value == true
end

-- The gathered frame under the cursor (walking up from each mouse focus).
local function FociRecord()
    local foci = _G.GetMouseFoci
    if type(foci) ~= "function" then return nil end
    local ok, list = pcall(foci)
    if not ok or type(list) ~= "table" then return nil end
    for _, region in ipairs(list) do
        local frame, depth = region, 0
        while type(frame) == "table" and frame ~= content and frame ~= UIParent and depth < 8 do
            if adopted[frame] then return frame, adopted[frame] end
            local okParent, parent = pcall(function() return frame.GetParent and frame:GetParent() end)
            frame, depth = okParent and parent or nil, depth + 1
        end
    end
    return nil
end

-- Kinds that can be moved (the pinned config tool never moves).
local MOVABLE = { libdbicon = true, blizzard = true, scan = true, radar = true }

local function CanPress(record, frame)
    if not record or record.pinned or not MOVABLE[record.kind] then return false end
    if record.set ~= current.set or #current.shown < 2 then return false end
    return not Protected(frame)
end

-- A Blizzard dropdown (tracking, compartment) opens its menu on the press;
-- a pickup closes it again. Both are insecure frames.
local function CloseMenus(frame)
    local candidates = { frame, frame.Button }
    local okKids, kids = pcall(function() return { frame:GetChildren() } end)
    if okKids and type(kids) == "table" then
        for _, child in ipairs(kids) do candidates[#candidates + 1] = child end
    end
    for _, button in ipairs(candidates) do
        if type(button) == "table" and type(button.IsMenuOpen) == "function"
            and type(button.CloseMenu) == "function" then
            local ok, open = pcall(button.IsMenuOpen, button)
            if ok and open then pcall(button.CloseMenu, button) end
        end
    end
end

local function EnsureGhost()
    if ghost then return ghost end
    ghost = CreateFrame("Frame", nil, UIParent)
    ghost:SetFrameStrata("TOOLTIP")
    ghost:SetSize(CELL, CELL)
    ghost:SetAlpha(GHOST_ALPHA)
    -- Mouse on: the release lands here, not on the button below.
    ghost:EnableMouse(true)
    ghost.plate = ghost:CreateTexture(nil, "BACKGROUND")
    ghost.plate:SetTexture(PLATE_TEXTURE)
    ghost.plate:SetAllPoints(ghost)
    ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
    ghost.icon:SetSize(CELL - 4, CELL - 4)
    ghost.icon:SetPoint("CENTER", ghost, "CENTER", 0, 0)
    ghost.edge = ghost:CreateTexture(nil, "OVERLAY")
    ghost.edge:SetSize(CELL + 2, CELL + 2)
    ghost.edge:SetPoint("CENTER", ghost, "CENTER", 0, 0)
    local icons = addon.VignetteRadarIconButton
    if icons and icons.ATLAS and icons.LayerCoords then
        ghost.edge:SetTexture(icons.ATLAS)
        ghost.edge:SetTexCoord(icons.LayerCoords("border"))
    else
        ghost.edge:SetTexture(PLATE_TEXTURE)
    end
    -- Keyboard only while dragging (never in combat: no pickups then).
    ghost:SetScript("OnKeyDown", function(self, key)
        local escape = key == "ESCAPE"
        -- Combat-restricted for insecure code; drags never run in combat.
        if self.SetPropagateKeyboardInput and not Locked() then
            pcall(self.SetPropagateKeyboardInput, self, not escape)
        end
        if escape then Cancel("escape") end
    end)
    ghost:Hide()
    PaintRings()
    return ghost
end
ButtonTray.GetGhost = function() return ghost end

-- Best-effort picture of the dragged button on the ghost.
local function GhostArt(frame, record)
    local icon = ghost.icon
    icon:Hide()
    icon:SetVertexColor(1, 1, 1, 1)
    local ok = pcall(function()
        if record.kind == "radar" then
            local icons = addon.VignetteRadarIconButton
            local name = record.name == "underlay" and (icons and icons.MINIMAP or "minimap")
                or ("corner_" .. tostring(frame.toolID or record.name))
            if icons and icons.HasIcon and icons.HasIcon(name) then
                icons.SetTexture(icon, name)
                local style = addon.VignetteRadarStyle
                if style and style.Color then icon:SetVertexColor(style.Color("iconGlyph")) end
                icon:Show()
                return
            end
        end
        local source = frame.icon or frame.art
        if not (source and source.GetTexture) then
            for _, region in ipairs({ frame:GetRegions() }) do
                if region.GetObjectType and region:GetObjectType() == "Texture" and region:IsShown() then
                    local layer = region:GetDrawLayer()
                    if (layer == "ARTWORK" or layer == "OVERLAY")
                        and (region:GetAtlas() or region:GetTexture()) then
                        source = region
                        break
                    end
                end
            end
        end
        if not source then return end
        local atlas = source.GetAtlas and source:GetAtlas()
        if atlas then
            icon:SetAtlas(atlas)
        else
            local texture = source:GetTexture()
            if not texture then return end
            icon:SetTexture(texture)
            icon:SetTexCoord(source:GetTexCoord())
        end
        icon:Show()
    end)
    if not ok then icon:Hide() end
end

local function PlaceGhost(x, y)
    if not (ghost and drag) then return end
    local ui = UIScale()
    local k = ghost._k or 1
    ghost:ClearAllPoints()
    ghost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", (x / ui + drag.dx) / k, (y / ui + drag.dy) / k)
end

-- Ends any press or drag and puts every reorder visual away.
local function Finish()
    local d = drag
    drag = nil
    if driver then driver:UnregisterEvent("GLOBAL_MOUSE_UP") end
    if not d then return end
    if ghost then
        ghost:EnableKeyboard(false)
        ghost:Hide()
    end
    if ring then ring:Hide() end
    local cell = d.record and d.record.cell
    if cell and cell._lifted then
        cell._lifted = false
        cell:SetAlpha(1)
        PaintCell(cell)
    end
end

Cancel = function(why)
    if not drag then return end
    local dragging = drag.state == "dragging"
    local name = drag.record and drag.record.name
    Finish()
    if dragging then
        Trace("reorder %s cancelled (%s)", tostring(name), why or "?")
        ButtonTray.Layout()
    end
end
ButtonTray.Cancel = function(why) Cancel(why) end

local function Pickup(x, y)
    local d = drag
    local index
    for i, record in ipairs(current.shown) do
        if record == d.record then index = i; break end
    end
    if Locked() or adopted[d.frame] ~= d.record or not index or #current.shown < 2
        or not (slot and slot:IsVisible()) then
        Finish()
        return false
    end
    CloseMenus(d.frame)
    EnsureGhost()
    GhostArt(d.frame, d.record)
    local k = Effective(content) / UIScale()
    ghost._k = k
    ghost:SetScale(k)
    -- Grab offset: the ghost keeps the cell's spot under the cursor.
    local cell = d.record.cell
    local cx, cy = cell:GetCenter()
    d.dx, d.dy = 0, 0
    if type(cx) == "number" and type(cy) == "number" then
        local ui, own = UIScale(), Effective(cell)
        d.dx, d.dy = cx * own / ui - x / ui, cy * own / ui - y / ui
    end
    cell._lifted = true
    cell:SetAlpha(LIFTED_ALPHA)
    PaintCell(cell)
    d.state, d.origin, d.slot, d.order, d.scrollWait = "dragging", index - 1, index - 1, nil, 0
    if GameTooltip and GameTooltip.IsOwned and GameTooltip:IsOwned(d.frame) then GameTooltip:Hide() end
    ghost:EnableKeyboard(true)
    if ghost.SetPropagateKeyboardInput then pcall(ghost.SetPropagateKeyboardInput, ghost, true) end
    ghost:Show()
    PlaceGhost(x, y)
    Trace("pickup %s from slot %d", d.record.name, index)
    ButtonTray.Layout()
    return drag ~= nil
end

-- Moves the gap to the slot under the cursor (nil outside). A cursor over
-- the gap itself keeps it, so a hold-and-release drops back in place.
local function UpdateSlot(x, y)
    local vx, vy = Local(x, y)
    local index, position = nil, nil
    if vx then
        index, position = ButtonTray.SlotAt(vx, vy, #(drag.order or {}), scrollRows[drag.set], current.visible)
    end
    if index and drag.slot and position == drag.slot then index = drag.slot end
    if index == drag.slot then return false, vy end
    drag.slot = index
    return true, vy
end

-- Scrolls while the cursor rests in the viewport's top or bottom band.
local function AutoScroll(vy, delta)
    if not (vy and drag.slot) then drag.scrollWait = 0; return end
    local height = current.visible * PITCH - GAP
    local rows, limit = scrollRows[drag.set] or 0, current.total - current.visible
    local step, depth = 0, 0
    if vy < EDGE and rows > 0 then step, depth = -1, EDGE - vy
    elseif vy > height - EDGE and rows < limit then step, depth = 1, vy - (height - EDGE) end
    if step == 0 then drag.scrollWait = 0; return end
    drag.scrollWait = drag.scrollWait + (delta or 0)
    local period = depth > EDGE / 2 and EDGE_FAST or EDGE_SLOW
    if drag.scrollWait >= period then
        drag.scrollWait = 0
        ButtonTray.Scroll(step)
    end
end

local function Commit()
    local d = drag
    local order = {}
    for index, record in ipairs(d.order or {}) do order[index] = record end
    table.insert(order, min(d.slot, #order) + 1, d.record)
    local changed = d.slot ~= d.origin
    Finish()
    if changed then
        -- The shown buttons take their new places; hidden ones keep theirs.
        local moving, list, taken = {}, lists[d.set], 0
        for _, record in ipairs(order) do moving[record] = true end
        for index, frame in ipairs(list) do
            if moving[adopted[frame]] then
                taken = taken + 1
                list[index] = order[taken].frame
            end
        end
        for index, frame in ipairs(list) do
            if adopted[frame] then adopted[frame].order = index end
        end
        Trace("reorder %s to slot %d", d.record.name, d.slot + 1)
        ButtonTray.SaveOrder(d.set)
    end
    ButtonTray.Layout()
    return changed
end

-- Test seams; the driver's GLOBAL_MOUSE_DOWN/UP and OnUpdate call these with
-- GetCursorPosition() (screen pixels).
function ButtonTray.Press(x, y)
    if drag or not (gathered and target == 1 and progress >= 1) then return false end
    if Locked() or AltDown() then return false end
    -- A press on a clipped-away cell is not a press on what the player sees.
    if not (viewport and viewport:IsVisible() and viewport:IsMouseOver()) then return false end
    local frame, record = FociRecord()
    if not CanPress(record, frame) then return false end
    drag = { state = "pressed", frame = frame, record = record, set = record.set, x0 = x, y0 = y, t = 0 }
    driver:RegisterEvent("GLOBAL_MOUSE_UP")
    driver:Show()
    return true
end

function ButtonTray.Move(x, y, delta)
    if not drag then return end
    if not MouseDown() then
        -- The release was missed (UI hidden, focus lost): treat it as one now.
        ButtonTray.Release(x, y)
        return
    end
    if drag.state == "pressed" then
        drag.t = drag.t + (delta or 0)
        local ui = UIScale()
        local dx, dy = (x - drag.x0) / ui, (y - drag.y0) / ui
        if dx * dx + dy * dy < DRAG_PX * DRAG_PX and drag.t < HOLD_SECONDS then return end
        if not Pickup(x, y) then return end
    end
    if not (slot and slot:IsVisible()) then Cancel("tray hidden"); return end
    PlaceGhost(x, y)
    local changed, vy = UpdateSlot(x, y)
    if changed then ButtonTray.Layout() end
    if drag then AutoScroll(vy, delta) end
end

function ButtonTray.Release(x, y)
    if not drag then return false end
    if drag.state == "pressed" then
        -- A plain click: the button handled it itself.
        Finish()
        return false
    end
    UpdateSlot(x, y)
    if drag.slot == nil then Cancel("dropped outside"); return false end
    return Commit()
end

function ButtonTray.DragState() return drag and drag.state or nil, drag and drag.slot, drag and drag.origin end
function ButtonTray.GetViewport() return viewport end
function ButtonTray.ScrollInfo()
    return scrollRows[current.set or "radar"] or 0, current.total, current.visible
end

local function Cursor()
    local get = _G.GetCursorPosition
    if type(get) ~= "function" then return 0, 0 end
    local ok, x, y = pcall(get)
    if ok and type(x) == "number" and type(y) == "number" then return x, y end
    return 0, 0
end

-- Events ---------------------------------------------------------------------

-- True while a menu opened from a gathered Blizzard button is up (tracking,
-- addon compartment): clicking in it must not slide the tray in.
local function KeepOpen()
    local cluster = _G.MinimapCluster
    local tracking = cluster and cluster.Tracking
    local compartment = _G.AddonCompartmentFrame
    local pairsToCheck = { { tracking, tracking and tracking.Button }, { compartment, compartment } }
    for _, entry in ipairs(pairsToCheck) do
        local holder, button = entry[1], entry[2]
        if holder and adopted[holder] and type(button) == "table" and type(button.IsMenuOpen) == "function" then
            local ok, open = pcall(button.IsMenuOpen, button)
            if ok and open then return true end
        end
    end
    return false
end

local function ClickedInside()
    local over = _G.MouseIsOver
    if type(over) ~= "function" then return true end
    if slot and slot:IsShown() and over(slot) then return true end
    if lip and lip:IsShown() and over(lip) then return true end
    return KeepOpen()
end

local function Signature()
    local tray = addon.VignetteRadarTray
    local face, host = nil, nil
    if tray and tray.Face then face, host = tray.Face() end
    local s = signature
    local changed = false
    local function Check(key, value)
        if s[key] ~= value then s[key] = value; changed = true end
    end
    Check("face", face)
    Check("main", tray and tray.Side and tray.Side() or false)
    Check("advanced", Settings().vignetteRadarAdvancedTools == true)
    if face then
        Check("left", face:GetLeft()); Check("top", face:GetTop())
        Check("w", face:GetWidth()); Check("h", face:GetHeight())
        Check("scale", HostScale(host))
        Check("strata", host:GetFrameStrata())
    end
    Check("screen", UIParent and UIParent.GetWidth and UIParent:GetWidth())
    return changed
end

local function OnUpdate(_, delta)
    if not gathered then Cancel("put away"); driver:Hide(); return end
    if drag then
        local x, y = Cursor()
        ButtonTray.Move(x, y, delta)
    end
    if scanWait then
        scanWait = scanWait - (delta or 0)
        if scanWait <= 0 then ButtonTray.Scan("addon loaded") end
    end
    if dirty then ButtonTray.Layout() end
    if progress ~= target then
        elapsed = min(SLIDE_SECONDS, elapsed + (delta or 0))
        local t = elapsed / SLIDE_SECONDS
        local eased = 1 - (1 - t) * (1 - t) * (1 - t)
        progress = t >= 1 and target or from + (target - from) * eased
        ButtonTray.Place()
        return
    end
    follow = follow + (delta or 0)
    if follow < FOLLOW_SECONDS then return end
    follow = 0
    if Signature() then ButtonTray.Layout() end
end

driver = CreateFrame("Frame")
driver:Hide()
driver:SetScript("OnUpdate", OnUpdate)
driver:RegisterEvent("PLAYER_REGEN_DISABLED")
driver:RegisterEvent("PLAYER_REGEN_ENABLED")
driver:RegisterEvent("GLOBAL_MOUSE_DOWN")
driver:RegisterEvent("ADDON_LOADED")
driver:SetScript("OnEvent", function(_, event, button)
    if event == "GLOBAL_MOUSE_UP" then
        if button == "LeftButton" or button == nil then ButtonTray.Release(Cursor()) end
        return
    end
    if event == "PLAYER_REGEN_DISABLED" then Cancel("combat") end
    if event == "GLOBAL_MOUSE_DOWN" then
        if drag then
            -- Right or middle button while dragging cancels; the press stays ours.
            if drag.state == "dragging" then Cancel(tostring(button or "button")) else Finish() end
            return
        end
        if (button == "LeftButton" or button == nil) and ButtonTray.Press(Cursor()) then return end
    end
    if event == "ADDON_LOADED" then
        -- One scan a moment after a burst of loads (throttled).
        if gathered and not scanWait and ButtonTray.CollectsMinimap() and Settings()[SCAN_KEY] ~= false then
            scanWait = SCAN_DELAY
            driver:Show()
        end
        return
    end
    if event == "PLAYER_REGEN_ENABLED" then
        local waiting = next(queued) ~= nil or retry
        if not waiting then return end
        retry = false
        for frame, entry in pairs(queued) do
            queued[frame] = nil
            if gathered and (entry.set == "radar" or ButtonTray.CollectsMinimap()) then
                Adopt(frame, entry.kind, entry.set, entry.name, entry.order)
            end
        end
        Trace("combat over: tray re-synced")
        ButtonTray.Sync()
        return
    end
    if not (gathered and target == 1) or ButtonTray.IsLocked() then return end
    if event == "GLOBAL_MOUSE_DOWN" and ClickedInside() then return end
    SetOpen(false, event == "PLAYER_REGEN_DISABLED" and "combat" or "click away")
end)

-- Repaints the surface, header buttons and cell plates for the theme.
function ButtonTray.RefreshTheme()
    if not content then return end
    local controls, tray = addon.VignetteRadarControls, addon.VignetteRadarTray
    if controls and controls.RefreshRoundedStatusSurface then controls.RefreshRoundedStatusSurface(content) end
    if tray and tray.SkinLikeRadar then tray.SkinLikeRadar(content) end
    if slot and slot._side and tray and tray.SquareJoin then tray.SquareJoin(content, slot._side) end
    if flip and flip.Refresh then flip:Refresh() end
    if lock and lock.RefreshLock then lock:RefreshLock() end
    for _, record in pairs(adopted) do PaintCell(record.cell) end
    PaintRings()
    for _, pool in pairs(spare) do
        for _, cell in ipairs(pool) do PaintCell(cell) end
    end
end

-- The Looks broadcast ends in Controls.RefreshTheme.
local controls = addon.VignetteRadarControls
if controls and type(controls.RefreshTheme) == "function" then
    local refreshControls = controls.RefreshTheme
    controls.RefreshTheme = function(...)
        refreshControls(...)
        ButtonTray.RefreshTheme()
    end
end

return ButtonTray
