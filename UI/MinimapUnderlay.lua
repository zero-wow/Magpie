local _, addon = ...
if type(addon) ~= "table" then return end

-- Minimap Underlay: Blizzard's own Minimap frame borrowed into the radar face,
-- so its terrain sits under the radar's rings and markers.
--   * The Minimap is re-parented to the radar panel, one frame level under
--     the face (the face is raised to make room), sized and masked to the face
--     (round mask on round faces, the face's rounded square on square faces).
--     Its mouse is off, so radar markers stay clickable and the wheel zooms
--     the radar.
--   * Layers: a backing in the face's background color sits under the
--     Minimap, the terrain draws over it at the Face Tint opacity, and the
--     face itself turns clear, so rings and markers stay on top.
--   * Fill match: the Minimap always fills the whole face. The radar draws
--     plotRadius px per range yards; the Minimap draws its half width per
--     C_Minimap.GetViewRadius() yards, so each zoom shows one fixed radar
--     range. The radar range snaps to the closest zoom's range; ranges far
--     wider than the widest zoom hide the terrain.
--   * Rotation follows North Up: north-up uses C_Minimap.SetIgnoreRotateMinimap
--     (no saved setting changes), turning needs the rotateMinimap CVar on.
--   * The hold: hooksecurefunc on the Minimap's layout methods (SetPoint,
--     SetParent, SetSize, SetMaskTexture, Show...) plus a cheap check on every
--     render notice anyone else moving it. Each drift is re-asserted once, on
--     the next frame, behind a re-entrancy guard (our own writes never count).
--     A re-assert writes every field the render check reads (and the mask,
--     shown state and alpha), so one write always heals one move.
--     More than REASSERT_CAP re-asserts inside REASSERT_WINDOW seconds means
--     another addon is fighting for it: the underlay backs off (2 s, doubling
--     to 60 s) and borrows again by itself after. An outside SetParent to a
--     frame that is not Blizzard's home is a hand-over: the underlay yields
--     and borrows again when that owner hides or lets go. Edit Mode gets the
--     Minimap back while open. While inactive, the hooks watch for another
--     addon restoring a copy of our old hold and re-home the Minimap. Every
--     drift, re-assert and give-back is logged under the "minimap" trace topic.
--   * HybridMinimap (some cities and indoor zones) is a child of the Minimap
--     pinned to the BACKGROUND strata, with its map pins at frame level 2000+.
--     Lifting it into the panel's strata would put those pins over the radar,
--     so it stays where Blizzard put it and the backing moves under it. Its
--     canvas takes the mouse and ignores Minimap:SetMaskTexture, so the mouse
--     is turned off and square faces swap in the face's mask.
--   * Everything is snapshotted when borrowed and restored exactly when given
--     back: parent, points, size, scale, strata, level, mouse, shown, mask,
--     zoom (and both zoom CVars), rotateMinimap and the ignore-rotate flag,
--     the HybridMinimap canvas mouse and mask, and the chrome it hid. Borrow
--     and give-back run only out of combat.
--   * Duplicate Icons: while terrain shows, both the minimap and the radar
--     would draw rares, treasures, quests and map spots. "Radar Wins" blanks
--     the minimap's blips (Minimap:SetBlipTexture) so only its terrain shows;
--     "Split By Type" leaves plain map spots (untimed area POIs) to the minimap
--     and keeps rares, treasures and quests on the radar; "Minimap Wins" hides
--     every radar marker kind the minimap also draws. The minimap's player
--     arrow is blanked in every mode: the radar draws its own center. The
--     engine defaults (ObjectIconsAtlas, MinimapArrow) go back when the
--     terrain hides, the mode changes or the Minimap is given back. The radar
--     reads one cached table (RadarHides) per render; nothing is per marker.
--   Underlay.Sync(range, panel) -> range   (called by Radar Render)
--   Underlay.FaceAlpha() / Refresh() / Toggle() / IsActive()
--   Underlay.IconMode() -> "radar" | "split" | "minimap"
--   Underlay.RadarHides() -> { areaPOIs, staticPOIs, vignettes, quests, label } or nil
local Underlay = {}
addon.VignetteRadarMinimapUnderlay = Underlay

local type, pcall, ipairs, tonumber, tostring = type, pcall, ipairs, tonumber, tostring
local abs, max, min = math.abs, math.max, math.min

local KEY, TINT_KEY, CHROME_KEY = "vignetteRadarMinimapUnderlay", "vignetteRadarMinimapUnderlayTint",
    "vignetteRadarMinimapUnderlayHideChrome"
local SHAPE_KEY = "vignetteRadarMinimapUnderlayShape"
local ICONS_KEY = "vignetteRadarMinimapUnderlayIcons"
-- A fully transparent texture (tools/generate_blank_media.py).
local BLANK = "Interface\\AddOns\\Magpie\\Media\\blank.tga"
-- Engine defaults: there is no getter, so these are what the give-back sets
-- (warcraft.wiki.gg API_Minimap_SetBlipTexture / API_Minimap_SetPlayerTexture).
local BLIP_DEFAULT = "Interface\\Minimap\\ObjectIconsAtlas"
local PLAYER_DEFAULT = "Interface\\Minimap\\MinimapArrow"
-- What the radar leaves out per Duplicate Icons mode, while terrain shows.
local HIDES = {
    radar = { label = "all shown (minimap icons blanked)" },
    split = { staticPOIs = true, label = "plain map spots hidden" },
    minimap = { areaPOIs = true, vignettes = true, quests = true, label = "minimap-drawn kinds hidden" },
}
Underlay.HIDES = HIDES
-- File ID, not "Textures\\MinimapMask": that path masks the map to nothing
-- on 12.0.7 (verified in game 2026-10-11; EllesmereUIMinimap uses this ID).
local ROUND_MASK = 186178
local SQUARE_MASK = "Interface\\ChatFrame\\ChatFrameBackground"
local ICON = "Interface\\AddOns\\Magpie\\Media\\radar-minimap-underlay.tga"
local CIRCLE_TEXTURE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local SQUARE_TEXTURE = "Interface\\AddOns\\Magpie\\Media\\radar-rounded-square.tga"
local FACE_ALPHA = .94
-- Half the minimap view diameter in yards per zoom (0 = widest), from
-- HereBeDragons' measured minimap sizes; calibrated live by GetViewRadius.
local RADII = {
    outdoor = { 233.333, 200, 166.667, 133.333, 100, 66.667 },
    indoor = { 150, 120, 90, 60, 40, 25 },
}
Underlay.RADII = RADII
-- Addons known to restyle or move the Minimap.
local OWNERS = { "SexyMap", "BasicMinimap", "EllesmereUIMinimap", "ElvUI", "FarmHud", "ls_Minimap",
    "MinimapButtonFrame", "SUI", "Leatrix_Plus", "HomeDecor" }
-- Re-asserts allowed inside one window before the underlay backs off.
local REASSERT_CAP, REASSERT_WINDOW = 6, 2
-- Backoff after a fight: first wait, longest wait, and how long a borrow must
-- last without a fight before the wait starts over at the first.
local BACKOFF_MIN, BACKOFF_MAX, BACKOFF_CALM = 2, 60, 30
-- Minimap methods an outside call of means someone moved or restyled it.
local HOLD_METHODS = { "SetPoint", "SetAllPoints", "ClearAllPoints", "SetSize", "SetWidth", "SetHeight",
    "SetParent", "SetScale", "SetMaskTexture", "SetFrameStrata", "SetFrameLevel", "Show", "Hide", "SetShown" }
Underlay.HOLD_METHODS = HOLD_METHODS
local HOOKED = {}
for _, name in ipairs(HOLD_METHODS) do HOOKED[name] = true end
-- Hook calls while inactive that can restore a copy of our old hold.
local WATCHED = { SetParent = true, SetPoint = true, SetAllPoints = true, SetSize = true }

local snapshot -- what the Minimap looked like before it was borrowed
local stale -- the snapshot kept from a give-up that left the Minimap half-borrowed
local active, pending, released, warned = false, false, false, false
local state = {} -- last applied view, to skip work when nothing changed
local tool, backing, hybridBacking, hybridMask, hooked
-- Magpie's own player arrow, drawn over the engine's arrow, which addons can
-- no longer hide (SetPlayerTexture is nil on 12.0.7). A shadow behind it keeps
-- it readable on any terrain; it turns with the player in north-up mode.
local arrowCover
local ARROW_SIZE, ARROW_SHADOW = 24, 30
local ARROW_TEXTURE = "Interface\\AddOns\\Magpie\\Media\\player-arrow.tga"
local written = {} -- CVar name -> the value this module last wrote
local lastZoomFix = 0
local applying = false -- our own Minimap writes in progress: the hooks ignore them
local drift -- cause of the re-assert waiting for the next frame, or nil
local hooksOn, hybridHooked = false, false
local reasserts, reassertAt = 0, 0
local recent = {} -- causes of the last few re-asserts, for the backoff trace
-- Backoff: the current wait (nil = none yet), when the pause ends, a token so
-- only the newest backoff timer acts, and when the current borrow began.
local backoff, pausedUntil, backoffToken, borrowedAt = nil, 0, 0, 0
local warnedFight = false
local leaving -- a give-up waiting for combat to end: { fight = true, cause = text }
local yieldTo -- the frame another addon took the Minimap into
local ownerHooked = setmetatable({}, { __mode = "k" })
local editing = false -- Edit Mode is open
local lastHome, defaultHome -- the last home given back to; Blizzard's home as first seen
local staleQueued = false

local function Settings() return addon.GetSettings() end

local function Print(text)
    local frame = _G.DEFAULT_CHAT_FRAME
    if frame and frame.AddMessage then frame:AddMessage("|cff7fd1b9Magpie|r: " .. text) end
end

local function Trace(fmt, ...)
    local trace = addon.Trace
    if trace and trace.Log then trace.Log("minimap", fmt, ...) end
end

local function Now() return type(GetTime) == "function" and GetTime() or 0 end

local function Locked()
    if addon.Bus and addon.Bus.InCombat() then return true end
    local lockdown = _G.InCombatLockdown
    if type(lockdown) ~= "function" then return false end
    local ok, value = pcall(lockdown)
    return ok and value == true
end

local function Map() return _G.Minimap end

-- Runs fn after delay seconds; false when there is no timer.
local function After(delay, fn)
    local timer = _G.C_Timer
    local after = timer and timer.After
    if type(after) ~= "function" then return false end
    after(delay, fn)
    return true
end

local function Paused() return Now() < pausedUntil end

-- A frame's name, or its nearest named parent's, for traces.
local function FrameName(frame)
    for _ = 1, 6 do
        if not frame then break end
        local name = frame.GetName and frame:GetName()
        if type(name) == "string" and name ~= "" then return name end
        frame = frame.GetParent and frame:GetParent() or nil
    end
    return "an unnamed frame"
end

-- Blizzard's own homes for the Minimap: never a takeover.
local function Container()
    local cluster = _G.MinimapCluster
    return cluster and cluster.MinimapContainer or nil
end

local function IsBlizzardHome(frame)
    return frame ~= nil and (frame == _G.MinimapCluster or frame == Container())
end

local function EditModeOpen()
    if editing then return true end
    local manager = _G.EditModeManagerFrame
    local open = manager and manager.IsEditModeActive
    if type(open) ~= "function" then return false end
    local ok, value = pcall(open, manager)
    return ok and value == true
end

-- With /vrtrace on: the first stack line outside this file and the C hook
-- wrapper, which names the addon (or Blizzard_*) that touched the Minimap.
local function Caller()
    local trace = addon.Trace
    if not (trace and trace.IsOn and trace.IsOn()) or type(_G.debugstack) ~= "function" then return nil end
    local ok, stack = pcall(_G.debugstack, 3, 6, 0)
    if not ok or type(stack) ~= "string" then return nil end
    for line in stack:gmatch("[^\n]+") do
        if not line:find("MinimapUnderlay", 1, true) and not line:find("^%[C%]") then return line:sub(1, 140) end
    end
end

local function GetCVar(name)
    local cvar = _G.C_CVar
    if cvar and cvar.GetCVar then
        local ok, value = pcall(cvar.GetCVar, name)
        if ok then return value end
    end
    return nil
end

local function SetCVar(name, value)
    local cvar = _G.C_CVar
    if not (cvar and cvar.SetCVar) or value == nil then return end
    written[name] = tostring(value)
    pcall(cvar.SetCVar, name, tostring(value))
end

local function MinimapCall(name, ...)
    local api = _G.C_Minimap
    local fn = api and api[name]
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok then return value end
end

local function HybridShown()
    local hybrid = _G.HybridMinimap
    return hybrid and hybrid.IsShown and hybrid:IsShown() == true
end

-- Runs fn with the hook guard up, so our own Minimap writes never count as
-- drift. Errors still reach the error handler.
local function Guard(fn, ...)
    applying = true
    local ok, err = pcall(fn, ...)
    applying = false
    if not ok then error(err, 0) end
end

-- Tells the Button Tray (UI/ButtonTray.lua) the underlay just borrowed (true)
-- or is giving back (false). A tray error never breaks the borrow or the
-- give-back; it is traced instead.
function Underlay.NotifyTray(on, panel)
    local tray = addon.VignetteRadarButtonTray
    if not (tray and tray.OnUnderlay) then return end
    local ok, err = pcall(tray.OnUnderlay, on, panel)
    if not ok then Trace("button tray %s failed: %s", on and "gather" or "release", tostring(err)) end
end

-- The first loaded addon that also manages the Minimap, or nil.
function Underlay.OtherOwner()
    local addons = _G.C_AddOns
    if not (addons and addons.IsAddOnLoaded) then return nil end
    for _, name in ipairs(OWNERS) do
        local ok, loaded = pcall(addons.IsAddOnLoaded, name)
        if ok and loaded then return name end
    end
end

-- Square faces mask with the face's own rounded square, so the terrain
-- matches the face edge exactly.
function Underlay.MaskFor(square) return square and SQUARE_TEXTURE or ROUND_MASK end

-- Zoom radii (yards, zoom 0 first) for where the player stands. The live
-- GetViewRadius at the current zoom picks indoor or outdoor and calibrates.
function Underlay.Radii()
    local map = Map()
    local levels = map and map.GetZoomLevels and tonumber(map:GetZoomLevels()) or 6
    local zoom = map and map.GetZoom and tonumber(map:GetZoom()) or 0
    local live = tonumber(MinimapCall("GetViewRadius"))
    local indoor = type(_G.IsIndoors) == "function" and _G.IsIndoors() == true
    local scale = 1
    if live and live > 0 then
        local out, inside = RADII.outdoor[zoom + 1], RADII.indoor[zoom + 1]
        if out and inside then
            indoor = abs(live / inside - 1) < abs(live / out - 1)
            local ratio = live / (indoor and inside or out)
            if ratio > .5 and ratio < 2 then scale = ratio end
        end
    end
    local base = indoor and RADII.indoor or RADII.outdoor
    local radii = {}
    for index = 1, max(1, min(levels, #base)) do radii[index] = base[index] * scale end
    return radii, indoor
end

-- Fill match. The Minimap always fills the whole face (maxHalf px half-wide),
-- so each zoom shows one fixed radar range: radius * plotRadius / maxHalf.
-- Returns the zoom closest to range, maxHalf and that range (whole yards);
-- a range past the widest zoom locks to it. nil only for bad input.
function Underlay.ZoomFor(range, plotRadius, maxHalf, radii)
    if not (tonumber(range) and range > 0 and plotRadius > 0 and maxHalf > 0 and #radii > 0) then return nil end
    -- Max zoom out: past the widest map zoom (0) the range locks to it, so
    -- the map never hides while the underlay is on. The radar's zoom steps
    -- stop there too (Underlay.Snap).
    local widest = radii[1] * plotRadius / maxHalf
    if range > widest then return 0, maxHalf, math.floor(widest + .5) end
    local best, bestGap, bestRange
    for index, radius in ipairs(radii) do
        local shown = radius * plotRadius / maxHalf
        local gap = abs(math.log(shown / range))
        if not bestGap or gap < bestGap then best, bestGap, bestRange = index - 1, gap, shown end
    end
    return best, maxHalf, math.floor(bestRange + .5)
end

local function FaceGeometry(panel)
    local field = panel and panel.field
    if not field then return nil end
    local square = panel.squarePlot == true
    local radius = tonumber(panel.fieldRadius) or 0
    -- The whole visible face: the background texture's size (square faces
    -- are fieldRadius across, round faces fill the field, 9 px wider).
    local background = field.background
    local width = background and background.GetWidth and tonumber(background:GetWidth()) or 0
    local maxHalf = width > 0 and width / 2 or (square and radius or radius + 9)
    return square, maxHalf, tonumber(panel.plotRadius) or 0
end

-- Chrome ---------------------------------------------------------------

local function HideChrome(map)
    local hidden = {}
    local cluster = _G.MinimapCluster
    if cluster and cluster.IsShown and cluster:IsShown() then
        cluster:Hide()
        hidden.cluster = true
    end
    -- Keep MinimapBackdrop shown (at alpha 0): its compass keeps turning,
    -- which encounter tools read for facing.
    local backdrop = _G.MinimapBackdrop
    if backdrop and backdrop.GetAlpha then
        hidden.backdropAlpha = backdrop:GetAlpha()
        backdrop:SetAlpha(0)
    end
    local landing = _G.ExpansionLandingPageMinimapButton
    if landing and landing.IsMouseEnabled then
        hidden.landingMouse = landing:IsMouseEnabled()
        landing:EnableMouse(false)
    end
    hidden.icons = {}
    -- The Button Tray (UI/ButtonTray.lua) gathers LibDBIcon buttons itself.
    local tray = addon.VignetteRadarButtonTray
    local gathered = tray and tray.CollectsMinimap and tray.CollectsMinimap() == true
    hidden.trayIcons = gathered == true
    if map.GetChildren and not gathered then
        for _, child in ipairs({ map:GetChildren() }) do
            local name = child.GetName and child:GetName()
            -- Buttons on the tray's ignore list are left alone.
            local ignored = tray and tray.IsIgnored and tray.IsIgnored(child, nil) == true
            if type(name) == "string" and name:find("^LibDBIcon10_") and child:IsShown() and not ignored then
                child:Hide()
                hidden.icons[#hidden.icons + 1] = child
            end
        end
    end
    return hidden
end

local function ShowChrome(hidden)
    if not hidden then return end
    if hidden.cluster and _G.MinimapCluster then _G.MinimapCluster:Show() end
    if hidden.backdropAlpha and _G.MinimapBackdrop then _G.MinimapBackdrop:SetAlpha(hidden.backdropAlpha) end
    if hidden.landingMouse ~= nil and _G.ExpansionLandingPageMinimapButton then
        _G.ExpansionLandingPageMinimapButton:EnableMouse(hidden.landingMouse)
    end
    for _, child in ipairs(hidden.icons or {}) do child:Show() end
end

-- Snapshot and restore ---------------------------------------------------

-- No mask getter exists: GetMinimapShape (set by minimap addons) says square.
local function HomeMask()
    local shape = type(_G.GetMinimapShape) == "function" and _G.GetMinimapShape()
    return shape == "SQUARE" and SQUARE_MASK or ROUND_MASK
end

local function Snapshot(map)
    local shot = { parent = map:GetParent(), points = {}, scale = map:GetScale(),
        strata = map:GetFrameStrata(), level = map:GetFrameLevel(), shown = map:IsShown(),
        mouse = map:IsMouseEnabled(), wheel = map:IsMouseWheelEnabled(),
        alpha = map.GetAlpha and map:GetAlpha() or 1, zoom = map:GetZoom(), zoomOut = GetCVar("minimapZoom"), zoomIn = GetCVar("minimapInsideZoom"),
        rotate = GetCVar("rotateMinimap"), ignoreRotate = MinimapCall("IsRotateMinimapIgnored") == true }
    shot.width, shot.height = map:GetWidth(), map:GetHeight()
    for index = 1, (map:GetNumPoints() or 0) do shot.points[index] = { map:GetPoint(index) } end
    shot.mask = HomeMask()
    local hit = map.ZoomHitArea
    if hit and hit.IsMouseEnabled then shot.hitMouse = hit:IsMouseEnabled() end
    return shot
end

-- True when the snapshot still shows our own hold (parent or anchor).
local function LooksBorrowed(shot, panel)
    if not (shot and panel) then return false end
    if shot.parent == panel then return true end
    for _, point in ipairs(shot.points or {}) do
        if point[2] == panel.field then return true end
    end
    return false
end

-- The layout half of a snapshot (no zoom, CVars, chrome or hybrid).
local function LayoutOf(shot)
    local points = {}
    for index, point in ipairs(shot.points) do points[index] = { point[1], point[2], point[3], point[4], point[5] } end
    return { parent = shot.parent, points = points, width = shot.width, height = shot.height, scale = shot.scale,
        alpha = shot.alpha, strata = shot.strata, level = shot.level, mask = shot.mask, mouse = shot.mouse,
        wheel = shot.wheel, hitMouse = shot.hitMouse, shown = shot.shown }
end

-- Blizzard's own home for the Minimap: as first seen in MinimapContainer
-- (with any Edit Mode scale), else the values from Blizzard_Minimap's
-- Minimap.xml (198 x 198, CENTER of MinimapContainer).
local function DefaultHome()
    local container = Container()
    if not container then return nil end
    if defaultHome and defaultHome.parent == container then return defaultHome end
    local strata = container.GetFrameStrata and container:GetFrameStrata() or "LOW"
    local level = (container.GetFrameLevel and tonumber(container:GetFrameLevel()) or 1) + 1
    return { parent = container, points = { { "CENTER", container, "CENTER", 0, 0 } }, width = 198, height = 198,
        scale = 1, alpha = 1, strata = strata, level = level, mask = HomeMask(), mouse = true, wheel = true,
        hitMouse = true, shown = true }
end

-- A home is valid when it is not our own panel and, for foreign frames, still
-- visible (a hidden HUD that let go is no home). Blizzard's cluster pieces are
-- always valid: the underlay itself hides the cluster.
local function HomeIsValid(shot, panel)
    local parent = shot and shot.parent
    if not parent or parent == panel or LooksBorrowed(shot, panel) then return false end
    if IsBlizzardHome(parent) or parent == _G.UIParent then return true end
    -- With the whole UI hidden (Alt-Z) nothing is visible: trust the home.
    local ui = _G.UIParent
    if ui and ui.IsVisible and not ui:IsVisible() then return true end
    if parent.IsVisible and not parent:IsVisible() then return false end
    return true
end

local function RestoreRotation(shot)
    if shot.rotate ~= nil and GetCVar("rotateMinimap") ~= shot.rotate then SetCVar("rotateMinimap", shot.rotate) end
    if not HybridShown() and (MinimapCall("IsRotateMinimapIgnored") == true) ~= shot.ignoreRotate then
        MinimapCall("SetIgnoreRotateMinimap", shot.ignoreRotate)
    end
end

local function RestoreFace(panel)
    if backing then backing:Hide() end
    if arrowCover then arrowCover:Hide(); arrowCover.fill:Hide(); arrowCover.shadow:Hide() end
    if hybridBacking then hybridBacking:Hide() end
    if not panel then return end
    if panel.field and state.fieldLevel then panel.field:SetFrameLevel(state.fieldLevel) end
    local background = panel.field and panel.field.background
    if background and background.GetVertexColor then
        local r, g, b = background:GetVertexColor()
        background:SetVertexColor(r, g, b, FACE_ALPHA)
    end
end

local function HybridCanvas()
    local hybrid = _G.HybridMinimap
    return hybrid and hybrid.MapCanvas or nil
end

local function RestoreHybrid(shot)
    local canvas = shot.hybrid and HybridCanvas()
    if not canvas then return end
    canvas:EnableMouse(shot.hybrid.mouse)
    canvas:EnableMouseWheel(shot.hybrid.wheel)
    if shot.hybrid.mask and canvas.SetMaskTexture and canvas:GetMaskTexture() ~= shot.hybrid.mask then
        canvas:SetMaskTexture(shot.hybrid.mask)
    end
end

-- Icons --------------------------------------------------------------------

-- Puts the engine's own blip and player-arrow textures back. Safe to call
-- when nothing was blanked.
local function RestoreIcons(map, shot)
    if not (map and shot) then return end
    if shot.blipsBlank then
        shot.blipsBlank = nil
        if map.SetBlipTexture then map:SetBlipTexture(BLIP_DEFAULT) end
        Trace("minimap blips restored")
    end
    if shot.arrowBlank then
        shot.arrowBlank = nil
        if map.SetPlayerTexture then map:SetPlayerTexture(PLAYER_DEFAULT) end
        Trace("minimap player arrow restored")
    end
end

-- Blanks the minimap's own icons: blips only in Radar Wins, the player arrow
-- in every mode (the radar draws its own center).
local function BlankIcons(map, shot, blips)
    if not (map and shot) then return end
    if blips and not shot.blipsBlank and map.SetBlipTexture then
        map:SetBlipTexture(BLANK)
        shot.blipsBlank = true
        Trace("minimap blips blanked")
    elseif not blips and shot.blipsBlank then
        shot.blipsBlank = nil
        map:SetBlipTexture(BLIP_DEFAULT)
        Trace("minimap blips restored")
    end
    if not shot.arrowBlank and map.SetPlayerTexture then
        map:SetPlayerTexture(BLANK)
        shot.arrowBlank = true
        Trace("minimap player arrow blanked")
    end
end

-- Puts the Minimap's layout back from home; zoom and the hybrid canvas come
-- from shot (the borrow's snapshot), which defaults to home.
local function RestoreMap(map, home, shot)
    shot = shot or home
    map:SetParent(home.parent)
    map:ClearAllPoints()
    for _, point in ipairs(home.points) do map:SetPoint(point[1], point[2], point[3], point[4], point[5]) end
    map:SetSize(home.width, home.height)
    map:SetScale(home.scale)
    if map.SetAlpha then map:SetAlpha(home.alpha or 1) end
    map:SetFrameStrata(home.strata)
    map:SetFrameLevel(home.level)
    map:SetMaskTexture(home.mask)
    map:EnableMouse(home.mouse)
    map:EnableMouseWheel(home.wheel)
    if home.hitMouse ~= nil and map.ZoomHitArea then map.ZoomHitArea:EnableMouse(home.hitMouse) end
    if shot.zoom and map:GetZoom() ~= shot.zoom then map:SetZoom(shot.zoom) end
    map:SetShown(home.shown)
    RestoreHybrid(shot)
end

-- W2UI -------------------------------------------------------------------
-- W2UI's minimap module lays the Minimap out itself (size, scale, point) and
-- animates a hover zoom by mouse position, even with the mouse off, so it
-- fights the hold every frame the cursor is over the radar. Its writers
-- pause while the underlay holds the map; its layout runs once on give-back.
local W2UI_PAUSED = { "ApplyLayout", "AnimateHoverZoom", "ApplyHoverZoomScale",
    "RefreshMinimapCanvas", "RefreshMinimapView" }
local w2uiSkipped = false

local function W2UIMinimap()
    local w2ui = _G.W2UI
    local modules = type(w2ui) == "table" and w2ui.Modules or nil
    local module = type(modules) == "table" and modules.Minimap or nil
    return type(module) == "table" and module or nil
end

local function PauseW2UI()
    local module = W2UIMinimap()
    if not module or module._vrPaused then return end
    module._vrPaused = true
    for _, name in ipairs(W2UI_PAUSED) do
        local original = module[name]
        if type(original) == "function" then
            module[name] = function(self, ...)
                if active then
                    if not w2uiSkipped then Trace("W2UI minimap %s paused while the underlay holds the map", name) end
                    w2uiSkipped = true
                    return
                end
                return original(self, ...)
            end
        end
    end
end

local function ResumeW2UI()
    if not w2uiSkipped then return end
    w2uiSkipped = false
    local module = W2UIMinimap()
    if not (module and type(module.ApplyLayout) == "function") then return end
    local ok, err = pcall(module.ApplyLayout, module)
    Trace("W2UI minimap layout re-run on give-back%s", ok and "" or (": " .. tostring(err)))
end

-- Gives the Minimap back exactly as it was. touchMap = false skips the
-- Minimap itself (another addon already took it).
local function Release(touchMap, cause)
    if not active then return true end
    if Locked() then
        pending = true
        Trace("give back (%s) waits for combat to end", cause or "?")
        return false
    end
    local map, shot = Map(), snapshot
    local radar = addon.VignetteRadarAPI
    local panel = radar and radar.GetPanel and radar.GetPanel()
    -- Textures go back even when the layout is left to another addon.
    if map and shot then Guard(RestoreIcons, map, shot) end
    if map and shot and touchMap ~= false then
        -- Only to a home that still works: never our own panel or a hidden
        -- foreign frame (another addon's HUD that let go meanwhile).
        local home = shot
        if not HomeIsValid(shot, panel) then
            home = DefaultHome() or shot
            Trace("home %s invalid: restoring Blizzard default", FrameName(shot.parent))
        end
        Guard(RestoreMap, map, home, shot)
        lastHome = LayoutOf(home)
    end
    -- Gathered buttons go home after the Minimap has its own size back
    -- (LibDBIcon places by its width) and before the chrome shows again.
    Underlay.NotifyTray(false, panel)
    if shot then
        if shot.zoomOut and GetCVar("minimapZoom") ~= shot.zoomOut then SetCVar("minimapZoom", shot.zoomOut) end
        if shot.zoomIn and GetCVar("minimapInsideZoom") ~= shot.zoomIn then
            SetCVar("minimapInsideZoom", shot.zoomIn)
        end
        RestoreRotation(shot)
        ShowChrome(shot.hidden)
    end
    RestoreFace(panel)
    Trace("gave back (%s)%s", cause or "?", touchMap == false and ", minimap left where it is" or "")
    -- Left half-borrowed: the next borrow must not snapshot our own layout.
    stale = touchMap == false and shot or nil
    active, pending, snapshot, state, drift, leaving = false, false, nil, {}, nil, nil
    reasserts, reassertAt = 0, 0
    if touchMap ~= false then ResumeW2UI() else w2uiSkipped = false end
    if tool and tool.Refresh then tool:Refresh() end
    return true
end

-- Renders the radar now, which borrows again through Sync when allowed.
local function RenderRadar()
    local radar = addon.VignetteRadarAPI
    if radar and radar.Refresh then radar.Refresh(false) end
end

local function RenderSoon()
    if not After(0, RenderRadar) then RenderRadar() end
end

-- Raises the radar face one level so the Minimap fits between the panel
-- and the face, keeping every descendant above its parent.
local function RaiseAbove(frame)
    local level = frame:GetFrameLevel()
    for _, child in ipairs({ frame:GetChildren() }) do
        if child ~= Map() and child.GetFrameLevel and child:GetFrameLevel() <= level then
            child:SetFrameLevel(level + 1)
        end
        if child ~= Map() and child.GetChildren then RaiseAbove(child) end
    end
end

-- The hold: where the Minimap lives while borrowed. Applied whole at borrow
-- and again after every drift. It writes every field Held checks (size
-- included), so a re-assert can never leave the check failing.
local function ApplyHold(map, panel)
    local base = panel:GetFrameLevel()
    if map:GetParent() ~= panel then map:SetParent(panel) end
    map:SetFrameStrata(panel:GetFrameStrata())
    map:SetFrameLevel(base + 1)
    map:SetScale(1)
    map:ClearAllPoints()
    map:SetPoint("CENTER", panel.field, "CENTER", 0, 0)
    -- The view's size, mask and shown state, once a view was applied.
    if state.width then map:SetSize(state.width, state.width) end
    if state.mask then map:SetMaskTexture(state.mask) end
    if state.terrain == true and not map:IsShown() then map:Show()
    elseif state.terrain == false and map:IsShown() then map:Hide() end
    if map.SetAlpha then map:SetAlpha(Underlay.MapAlpha()) end
    map:EnableMouse(false)
    map:EnableMouseWheel(false)
    if map.ZoomHitArea and map.ZoomHitArea.EnableMouse then map.ZoomHitArea:EnableMouse(false) end
end

-- True while the hold stands; else false and what gave way. Four cheap
-- reads, run every render, for drift the hooks cannot see.
local function Held(map, panel)
    if map:GetParent() ~= panel then return false, "parent" end
    if map:GetNumPoints() ~= 1 then return false, "points" end
    local _, relative = map:GetPoint(1)
    if relative ~= panel.field then return false, "anchor" end
    if map:GetScale() ~= 1 then return false, "scale" end
    if state.width and map:IsShown() and abs(map:GetWidth() - state.width) > .5 then return false, "size" end
    return true
end

local function CurrentPanel()
    local radar = addon.VignetteRadarAPI
    local panel = radar and radar.GetPanel and radar.GetPanel()
    return panel or state.panel
end

-- The give-back Sync must finish before anything else: its cause and
-- whether to touch the Minimap (nil for a fight: decided at give-back).
local function Leaving()
    if leaving then return leaving.cause, nil end
    if yieldTo then return "taken by " .. FrameName(yieldTo), false end
    if editing then return "edit mode", true end
end

-- Gives the Minimap up. A fight backs off (BACKOFF_MIN doubling to
-- BACKOFF_MAX seconds) and borrows again by itself after. In combat the
-- give-back waits (Release sets pending) and Sync finishes it after, with no
-- re-asserts meanwhile.
local function Leave(touchMap, cause)
    local plan = leaving
    if plan and plan.fight then
        local map, panel = Map(), CurrentPanel()
        -- Still in our panel: we wrote last, so the home is known and nobody
        -- else holds it. Else another addon has it: leave its layout alone.
        touchMap = map ~= nil and panel ~= nil and map:GetParent() == panel
        cause = plan.cause
    end
    if not Release(touchMap, cause) then return false end
    if plan and plan.fight then
        backoff = backoff and min(backoff * 2, BACKOFF_MAX) or BACKOFF_MIN
        pausedUntil = Now() + backoff
        backoffToken = backoffToken + 1
        local token = backoffToken
        Trace("backing off %ds (minimap %s)", backoff, touchMap and "put back home" or "left where it is")
        local function Over()
            if token ~= backoffToken then return end
            if Paused() then
                After(pausedUntil - Now(), Over)
                return
            end
            Trace("backoff over: borrow allowed again")
            RenderRadar()
        end
        After(backoff, Over)
    end
    return true
end

-- Puts the hold back after someone else moved the Minimap. Capped: a fight
-- (another addon re-moving it every time) ends in a backoff.
local function Reassert()
    local cause = drift
    drift = nil
    if not (active and cause) or Leaving() then return end
    local map, panel = Map(), CurrentPanel()
    if not (map and panel and panel.field) then return end
    -- An event or render check whose problem is gone by now: redraw only,
    -- nothing is counted.
    if not HOOKED[cause] and Held(map, panel) then
        state.key = nil
        RenderRadar()
        return
    end
    local now = Now()
    if now - reassertAt > REASSERT_WINDOW then reassertAt, reasserts = now, 0 end
    reasserts = reasserts + 1
    recent[#recent + 1] = cause
    if #recent > REASSERT_CAP then table.remove(recent, 1) end
    if reasserts > REASSERT_CAP then
        local other = Underlay.OtherOwner()
        Trace("fight: %d re-asserts in %ds (%s), owner %s", reasserts, REASSERT_WINDOW, table.concat(recent, ", "),
            other or "unknown")
        if not warnedFight then
            warnedFight = true
            Print((other or "another addon") .. " keeps moving the minimap. Minimap Underlay steps back and tries again later.")
        end
        -- Counters reset first: in combat the give-back waits, and the next
        -- frames must not land here (and print) again.
        reasserts, reassertAt = 0, 0
        leaving = { fight = true, cause = "fight over the minimap" }
        Leave()
        return
    end
    if Locked() and map.IsProtected and map:IsProtected() then
        pending = true
        Trace("re-assert after %s waits for combat to end", cause)
        return
    end
    Trace("re-assert #%d after %s", reasserts, cause)
    Guard(ApplyHold, map, panel)
    -- The mask stays known (ApplyHold re-applied it); the view is redrawn.
    state.key = nil
    RenderRadar()
end

-- Something outside this module touched the Minimap: one re-assert, next frame.
-- Debug: /run VignetteRadarUnderlayFreeze(true) stops every re-assert and
-- view write, so hand tests on the borrowed Minimap stick. false resumes.
local frozen = false
_G.VignetteRadarUnderlayFreeze = function(on)
    frozen = on == true
    state.key = nil
    Print("underlay " .. (frozen and "frozen: /run tests on Minimap stick" or "resumed"))
end

local function Drift(cause)
    if frozen or not active or applying or drift or Leaving() then return end
    drift = cause
    local from = HOOKED[cause] and Caller()
    if from then Trace("drift: %s from %s", cause, from) else Trace("drift: %s", cause) end
    if not After(0, Reassert) then Reassert() end
end

-- The owner we yielded to let go: borrowing is allowed again.
local function OwnerLetGo(why)
    if not yieldTo then return end
    Trace("minimap owner %s let go (%s): borrow allowed again", FrameName(yieldTo), why)
    yieldTo = nil
    released = false
    RenderSoon()
end

local function HookOwner(owner)
    if ownerHooked[owner] or owner == _G.UIParent or not owner.HookScript then return end
    ownerHooked[owner] = true
    owner:HookScript("OnHide", function(self) if yieldTo == self then OwnerLetGo("owner hidden") end end)
end

-- An outside SetParent to a frame that is not Blizzard's: a hand-over, never
-- a fight (Blizzard never re-parents the Minimap). Give it up and wait for
-- that owner to hide or re-parent it.
local function Takeover(owner)
    local name = FrameName(owner)
    local own = owner.GetName and owner:GetName()
    Trace("minimap taken by %s (parent %s)", name, type(own) == "string" and own or "unnamed")
    yieldTo, drift = owner, nil
    HookOwner(owner)
    Release(false, "taken by " .. name)
end

-- True while the Minimap sits in our panel or hangs off its face.
local function InOurPanel(map, panel)
    if map:GetParent() == panel then return true end
    for index = 1, (map:GetNumPoints() or 0) do
        local _, relative = map:GetPoint(index)
        if relative == panel.field then return true end
    end
    return false
end

-- Inactive, yet the Minimap is in our panel: another addon restored a copy
-- of our old hold (it snapshotted the Minimap while we held it). Re-home it;
-- the normal borrow then starts from a clean state when the underlay is on.
local function CheckStaleHome()
    staleQueued = false
    if active or applying then return end
    local map, panel = Map(), CurrentPanel()
    if not (map and panel and panel.field and map.GetParent and map.GetNumPoints) then return end
    if not InOurPanel(map, panel) then return end
    if Locked() then
        pending = true
        Trace("re-home waits for combat to end")
        return
    end
    local home = stale and HomeIsValid(stale, panel) and stale
        or lastHome and HomeIsValid(lastHome, panel) and lastHome or DefaultHome()
    if not home then return end
    Trace("someone restored our old hold while inactive: re-homing to %s", FrameName(home.parent))
    Guard(RestoreMap, map, home, {})
    stale = nil
    if Underlay.IsEnabled() and panel:IsShown() then RenderSoon() end
end

local function QueueStaleCheck()
    if staleQueued then return end
    staleQueued = true
    if not After(0, CheckStaleHome) then CheckStaleHome() end
end

-- Hook calls while inactive: follow the owner we yielded to, and look for a
-- restored copy of our old hold.
local function Watch(name, map)
    if yieldTo and name == "SetParent" then
        local parent = map:GetParent()
        if parent ~= yieldTo then
            if parent and parent ~= CurrentPanel() and not IsBlizzardHome(parent) then
                Trace("minimap passed on to %s", FrameName(parent))
                yieldTo = parent
                HookOwner(parent)
            else
                OwnerLetGo("re-parented")
            end
        end
    end
    if WATCHED[name] then QueueStaleCheck() end
end

local function InstallHooks(map)
    if hooksOn or type(_G.hooksecurefunc) ~= "function" then return end
    hooksOn = true
    for _, name in ipairs(HOLD_METHODS) do
        if type(map[name]) == "function" then
            _G.hooksecurefunc(map, name, function()
                if applying or frozen then return end
                if not active then Watch(name, map); return end
                if name == "SetParent" then
                    local parent = map:GetParent()
                    if parent and parent ~= CurrentPanel() and not IsBlizzardHome(parent) then
                        Takeover(parent)
                        return
                    end
                end
                Drift(name)
            end)
        end
    end
end

local function Borrow(panel)
    local map = Map()
    if not (map and panel and panel.field and map.SetMaskTexture) then return false end
    if Locked() then pending = true; return false end
    PauseW2UI()
    local other = Underlay.OtherOwner()
    if other and not warned then
        warned = true
        Print(other .. " also manages the minimap. Minimap Underlay borrows it while on and gives it back when off.")
    end
    snapshot = Snapshot(map)
    -- Blizzard's own home as it really is (Edit Mode scale included).
    if snapshot.parent == Container() and not LooksBorrowed(snapshot, panel) then defaultHome = LayoutOf(snapshot) end
    if stale and (LooksBorrowed(snapshot, panel) or not HomeIsValid(snapshot, panel)) then
        Trace("minimap still half-borrowed: keeping the earlier snapshot for the give-back")
        stale.hidden = nil
        snapshot = stale
    end
    stale = nil
    local base = panel:GetFrameLevel()
    state = { fieldLevel = panel.field:GetFrameLevel(), panel = panel }
    if state.fieldLevel < base + 3 then
        panel.field:SetFrameLevel(base + 3)
        RaiseAbove(panel.field)
    end
    InstallHooks(map)
    Guard(ApplyHold, map, panel)
    if Settings()[CHROME_KEY] ~= false then snapshot.hidden = HideChrome(map) end
    if not backing then
        backing = panel:CreateTexture(nil, "ARTWORK")
    end
    backing:ClearAllPoints()
    backing:SetAllPoints(panel.field.background)
    backing:Show()
    active, pending, released, drift, leaving = true, false, false, nil, nil
    reasserts, reassertAt, borrowedAt = 0, 0, Now()
    Trace("borrowed from %s (%sx%s, zoom %s, %s)", snapshot.parent and snapshot.parent.GetName
        and snapshot.parent:GetName() or "?", snapshot.width or 0, snapshot.height or 0,
        tostring(snapshot.zoom), other or "no other minimap addon")
    Underlay.NotifyTray(true, panel)
    if tool and tool.Refresh then tool:Refresh() end
    return true
end

-- Rotation: north-up ignores the rotate CVar; turning needs it on.
local function ApplyRotation(northUp)
    if HybridShown() then return end
    local rotate = GetCVar("rotateMinimap") == "1"
    if northUp then
        if (MinimapCall("IsRotateMinimapIgnored") == true) ~= rotate then
            MinimapCall("SetIgnoreRotateMinimap", rotate)
        end
    else
        if MinimapCall("IsRotateMinimapIgnored") == true then MinimapCall("SetIgnoreRotateMinimap", false) end
        if not rotate then SetCVar("rotateMinimap", "1") end
    end
end

local function TintAlpha()
    local value = tonumber(Settings()[TINT_KEY]) or .5
    return max(.1, min(.9, value))
end

function Underlay.IsEnabled() return Settings()[KEY] == true end
function Underlay.IsActive() return active end
-- True while the borrowed terrain is drawn in the face.
function Underlay.ShowsTerrain() return active == true and state.terrain == true end
function Underlay.IsPending() return pending end
-- The disc that covers the engine's player arrow (tests read it).
function Underlay.ArrowCover() return arrowCover end
-- True while backing off after a fight over the Minimap.
function Underlay.IsPaused() return Paused() end
-- The frame another addon took the Minimap into, while the underlay yields.
function Underlay.YieldedTo() return yieldTo end

-- The face background's alpha. While terrain shows, the face sits over the
-- Minimap and carries the Face Tint: the stack is backing, terrain, the
-- tinted face, then the radar's rings and markers.
function Underlay.FaceAlpha()
    if active and state.terrain then return TintAlpha() end
    return FACE_ALPHA
end

-- The Minimap always draws opaque: below alpha 1 the engine redraws indoor
-- floor-plan art black on the next zoom (found in game 2026-10-12). The
-- tint is the face's job (FaceAlpha).
function Underlay.MapAlpha() return 1 end

-- The face's normal alpha, without the terrain tint. Panels skinned like
-- the radar use this, so the minimap showing through never thins them.
function Underlay.BaseAlpha() return FACE_ALPHA end

-- HybridMinimap --------------------------------------------------------------

local function HookHybrid(hybrid)
    if hybridHooked or not (hybrid and hybrid.HookScript) then return end
    hybridHooked = true
    local function Changed(self)
        if not active then return end
        state.key = nil
        Trace("hybrid minimap %s", self:IsShown() and "shown" or "hidden")
    end
    hybrid:HookScript("OnShow", Changed)
    hybrid:HookScript("OnHide", Changed)
end

-- A backing under the HybridMinimap: the hybrid is fixed to the BACKGROUND
-- strata (frame level 100), so the panel's own backing would cover it.
local function EnsureHybridBacking(panel)
    if hybridBacking then return hybridBacking end
    hybridBacking = CreateFrame("Frame", nil, panel)
    hybridBacking:SetFrameStrata("BACKGROUND")
    if hybridBacking.SetFixedFrameStrata then hybridBacking:SetFixedFrameStrata(true) end
    hybridBacking:SetFrameLevel(1)
    hybridBacking:EnableMouse(false)
    hybridBacking.texture = hybridBacking:CreateTexture(nil, "ARTWORK")
    hybridBacking:Hide()
    return hybridBacking
end

-- The hybrid's canvas takes the mouse over the whole face and keeps its own
-- round mask: mouse off, and square faces swap in the face's mask.
local function ApplyHybrid(mask)
    local hybrid = _G.HybridMinimap
    if not hybrid then return end
    HookHybrid(hybrid)
    local canvas = hybrid.MapCanvas
    if not (canvas and snapshot) then return end
    if not snapshot.hybrid then
        snapshot.hybrid = { mouse = canvas:IsMouseEnabled(), wheel = canvas:IsMouseWheelEnabled(),
            mask = canvas.GetMaskTexture and canvas:GetMaskTexture() or nil }
        canvas:EnableMouse(false)
        canvas:EnableMouseWheel(false)
        Trace("hybrid canvas held: mouse off")
    end
    if not (canvas.SetMaskTexture and canvas.GetMaskTexture and hybrid.CreateMaskTexture) then return end
    local want = snapshot.hybrid.mask
    if mask == SQUARE_TEXTURE then
        if not hybridMask then
            hybridMask = hybrid:CreateMaskTexture()
            hybridMask:SetTexture(SQUARE_TEXTURE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            hybridMask:SetAllPoints(hybrid)
        end
        want = hybridMask
    end
    if want and canvas:GetMaskTexture() ~= want then canvas:SetMaskTexture(want) end
end

-- View ------------------------------------------------------------------------

local function Paint(panel)
    local background = panel.field.background
    local style = addon.VignetteRadarStyle
    local r, g, b = .015, .022, .028
    if style and style.Color then r, g, b = style.Color("background") end
    background:SetVertexColor(r, g, b, Underlay.FaceAlpha())
    local hybrid = state.hybrid == true
    local texture = state.square and SQUARE_TEXTURE or CIRCLE_TEXTURE
    if backing then
        backing:SetTexture(texture)
        backing:SetVertexColor(r, g, b, FACE_ALPHA)
        backing:SetShown(not hybrid)
    end
    if hybrid then
        local under = EnsureHybridBacking(panel)
        under.texture:ClearAllPoints()
        under.texture:SetAllPoints(background)
        under.texture:SetTexture(texture)
        under.texture:SetVertexColor(r, g, b, FACE_ALPHA)
        under:Show()
    elseif hybridBacking then
        hybridBacking:Hide()
    end
    -- Magpie's player dot wins over the minimap arrow, except in Minimap Wins.
    local cover = state.terrain == true and Underlay.IconMode() ~= "minimap"
    if cover and not arrowCover then
        local field = panel.field
        arrowCover = CreateFrame("Frame", nil, field)
        arrowCover:SetSize(1, 1)
        arrowCover:SetPoint("CENTER", field, "CENTER", 0, 0)
        -- Textures on the field itself, so the radar's dot (OVERLAY) stays on top.
        arrowCover.shadow = field:CreateTexture(nil, "ARTWORK", nil, 6)
        arrowCover.shadow:SetTexture(ARROW_TEXTURE)
        arrowCover.shadow:SetSize(ARROW_SHADOW, ARROW_SHADOW)
        arrowCover.shadow:SetPoint("CENTER", field, "CENTER", 0, -1)
        arrowCover.shadow:SetVertexColor(0, 0, 0, .7)
        arrowCover.fill = field:CreateTexture(nil, "ARTWORK", nil, 7)
        arrowCover.fill:SetTexture(ARROW_TEXTURE)
        arrowCover.fill:SetSize(ARROW_SIZE, ARROW_SIZE)
        arrowCover.fill:SetPoint("CENTER", field, "CENTER", 0, 0)
        arrowCover:SetScript("OnUpdate", function(self)
            local angle = 0
            if Settings().vignetteRadarNorthUp == true and type(_G.GetPlayerFacing) == "function" then
                local ok, facing = pcall(_G.GetPlayerFacing)
                angle = ok and tonumber(facing) or 0
            end
            if angle ~= self.angle then
                self.angle = angle
                self.fill:SetRotation(angle)
                self.shadow:SetRotation(angle)
            end
        end)
        arrowCover:SetScript("OnShow", function(self) self.fill:Show(); self.shadow:Show() end)
        arrowCover:SetScript("OnHide", function(self) self.fill:Hide(); self.shadow:Hide() end)
    end
    if arrowCover then
        local ar, ag, ab = 1, .82, .3
        if style and style.Color then ar, ag, ab = style.Color("accent") end
        arrowCover.fill:SetVertexColor(ar, ag, ab, 1)
        arrowCover:SetShown(cover)
        arrowCover.fill:SetShown(cover)
        arrowCover.shadow:SetShown(cover)
    end
    local map = Map()
    if map and map.SetAlpha then map:SetAlpha(Underlay.MapAlpha()) end
end

local function ApplyView(map, panel, mask, zoom, half, northUp, mode)
    if mask ~= state.mask then
        map:SetMaskTexture(mask)
        state.mask = mask
    end
    local terrain = zoom ~= nil
    state.terrain = terrain
    local hide = terrain and HIDES[mode] or nil
    if hide ~= state.hide then
        state.hide = hide
        Trace("duplicate icons: %s, radar markers %s", hide and mode or "terrain off", hide and hide.label or "all shown")
    end
    if terrain then
        if map:GetZoom() ~= zoom then map:SetZoom(zoom) end
        state.zoom, state.width = zoom, half * 2
        map:SetSize(half * 2, half * 2)
        if not map:IsShown() then map:Show() end
        BlankIcons(map, snapshot, mode == "radar")
    else
        state.zoom, state.width = nil, nil
        if map:IsShown() then map:Hide() end
        RestoreIcons(map, snapshot)
    end
    ApplyHybrid(mask)
    ApplyRotation(northUp)
    Paint(panel)
end

-- Called by the radar each render with the range it is about to draw.
-- Returns the range to draw (snapped while the underlay is on).
function Underlay.Sync(range, panel)
    if not (panel and panel.field) then return range end
    Underlay.EnsureTool(panel)
    if not Underlay.IsEnabled() then
        if active then Release(true, "turned off") end
        return range
    end
    local map = Map()
    if not map then return range end
    if frozen and active then return state.drawn or range end
    if active then
        -- A give-up, hand-over or Edit Mode give-back waiting for combat.
        local leave, touch = Leaving()
        if leave then
            if not Locked() then Leave(touch, leave) end
            if active then return state.drawn or range end
            return range
        end
        local held, why = Held(map, panel)
        if not held then
            Drift("check: " .. why)
            -- Given up, or the re-assert runs next frame: draw as before for now.
            if not active or drift then return state.drawn or range end
        elseif backoff and Now() - borrowedAt >= BACKOFF_CALM then
            backoff = nil
            Trace("held %ds without a fight: backoff reset", BACKOFF_CALM)
        end
    elseif released or Paused() or yieldTo or EditModeOpen() or not Borrow(panel) then
        return range
    end
    local square, maxHalf, plotRadius = FaceGeometry(panel)
    -- Circle shape: a round map exactly the size of the outer range ring,
    -- so the ring's yards and the terrain's edge are the same circle.
    local circle = Underlay.Shape() == "circle"
    if circle then maxHalf = plotRadius end
    local radii = state.radii
    if not radii then radii, state.indoor = Underlay.Radii(); state.radii = radii end
    local zoom, half, drawn = Underlay.ZoomFor(range, plotRadius, maxHalf, radii)
    local style = addon.VignetteRadarStyle
    local northUp = Settings().vignetteRadarNorthUp == true
    local hybrid = HybridShown() == true
    local mode = Underlay.IconMode()
    local key = table.concat({ tostring(zoom), tostring(half), square and 1 or 0, northUp and 1 or 0,
        style and style.revision or 0, TintAlpha(), circle and 1 or 0, hybrid and 1 or 0, mode }, ":")
    if key == state.key then return drawn or range end
    -- Size changes stay out of combat when something protected hangs off the Minimap.
    local guarded = map.IsProtected and map:IsProtected()
    if guarded and Locked() then pending = true; return drawn or range end
    state.key, state.square, state.hybrid, state.drawn = key, square, hybrid, drawn
    Guard(ApplyView, map, panel, Underlay.MaskFor(square and not circle), zoom, half, northUp, mode)
    return drawn or range
end

-- The range Sync would draw for range, without touching anything. The
-- radar's zoom steps use it to skip steps that snap to the same map zoom.
function Underlay.Snap(range, panel)
    if not (active and panel and panel.field) then return range end
    local _, maxHalf, plotRadius = FaceGeometry(panel)
    if Underlay.Shape() == "circle" then maxHalf = plotRadius end
    local radii = state.radii or Underlay.Radii()
    local zoom, _, drawn = Underlay.ZoomFor(range, plotRadius, maxHalf, radii)
    return zoom and drawn or range
end

-- Duplicate Icons mode: "radar" (blank the minimap's icons), "split" (plain
-- map spots go to the minimap) or "minimap" (the radar hides shared kinds).
function Underlay.IconMode()
    local value = Settings()[ICONS_KEY]
    return HIDES[value] and value or "radar"
end

-- The marker kinds the radar leaves out this render, or nil when the terrain
-- is not showing. One cached table: the radar reads it once per render.
function Underlay.RadarHides() return state.hide end

-- Re-reads settings and borrows or gives back right away when possible.
-- user = a settings change, which also ends a backoff early.
local function Refresh(user)
    state.key, state.radii = nil, nil
    CheckStaleHome()
    if user and Paused() then
        pausedUntil = 0
        Trace("settings changed: backoff ended early")
    end
    local radar = addon.VignetteRadarAPI
    local panel = radar and radar.GetPanel and radar.GetPanel()
    if not Underlay.IsEnabled() or not (panel and panel:IsShown()) then
        released = false
        Release(true, Underlay.IsEnabled() and "radar hidden" or "turned off")
    else
        released = false
        -- A changed chrome choice needs a fresh borrow.
        if active and (Settings()[CHROME_KEY] ~= false) ~= (snapshot and snapshot.hidden ~= nil) then
            Release(true, "chrome setting changed")
        end
        -- The Button Tray started or stopped taking LibDBIcon buttons: the
        -- chrome must hide (or leave) them afresh.
        local tray = addon.VignetteRadarButtonTray
        local hidden = snapshot and snapshot.hidden
        if active and hidden and tray and tray.CollectsMinimap
            and (hidden.trayIcons == true) ~= (tray.CollectsMinimap() == true) then
            Release(true, "button tray setting changed")
        end
        if radar.Refresh then radar.Refresh(false) end
    end
    if tool and tool.Refresh then tool:Refresh() end
end

function Underlay.Refresh() Refresh(true) end

-- Edit Mode re-anchors and scales Blizzard's minimap system, which needs the
-- real Minimap home while it is open: give it back, borrow again on exit.
function Underlay.OnEditMode(open)
    editing = open == true
    Trace("edit mode %s: minimap %s", editing and "on" or "off", editing and "given back" or "borrowed again")
    if editing then
        if active then Release(true, "edit mode") end
    else
        released = false
        RenderSoon()
    end
end

function Underlay.Toggle()
    local schema = addon.Schema
    local value = not Underlay.IsEnabled()
    if schema and schema.Set and schema.Entry(KEY) then schema.Set(KEY, value)
    else Settings()[KEY] = value; Underlay.Refresh() end
end

-- "square" fills the whole face (the face's own shape); "circle" fits the
-- outer range ring.
function Underlay.Shape()
    return Settings()[SHAPE_KEY] == "circle" and "circle" or "square"
end

function Underlay.ToggleShape()
    local schema = addon.Schema
    local value = Underlay.Shape() == "circle" and "square" or "circle"
    if schema and schema.Set and schema.Entry(SHAPE_KEY) then schema.Set(SHAPE_KEY, value)
    else Settings()[SHAPE_KEY] = value; Underlay.Refresh() end
end

-- Corner toggle -----------------------------------------------------------

local function ToolState(self)
    local on = Underlay.IsEnabled()
    -- Layered like the other corner tools (UI/IconButton.lua).
    local icons = addon.VignetteRadarIconButton
    if self.iconLayers and icons then
        icons.Paint(self, on, self._hovered == true)
        return
    end
    local row = (on and 2 or 0) + (self._hovered and 1 or 0)
    self.art:SetTexCoord(1 / 64, 63 / 64, (row * 64 + 1) / 256, (row * 64 + 63) / 256)
    local style = addon.VignetteRadarStyle
    local r, g, b = .69, .77, .78
    if style and style.Color then r, g, b = style.Color("accent") end
    self.art:SetVertexColor(r, g, b, 1)
end

-- A small button in the bottom-right corner grid's free outer slot (under
-- Auto Route), shown with the other corner tools (it follows the "Stay
-- Fully Visible" tool's visibility). Right-click flips the map shape.
function Underlay.EnsureTool(panel)
    if tool or not (panel and panel.field and panel.hoverTools) then return tool end
    tool = CreateFrame("Button", nil, panel.field)
    tool:SetSize(16, 16)
    tool:SetFrameLevel(panel.field:GetFrameLevel() + 8)
    tool:SetPoint("BOTTOMRIGHT", panel.field, "BOTTOMRIGHT", -12, 12)
    tool:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local icons = addon.VignetteRadarIconButton
    if icons and icons.AddLayers and icons.HasIcon(icons.MINIMAP) then
        icons.AddLayers(tool, icons.MINIMAP, 18)
    else
        tool.art = tool:CreateTexture(nil, "ARTWORK")
        tool.art:SetTexture(ICON)
        tool.art:SetSize(18, 18)
        tool.art:SetPoint("CENTER")
    end
    tool.Refresh = ToolState
    tool:SetScript("OnClick", function(self, button)
        if button == "RightButton" then Underlay.ToggleShape() else Underlay.Toggle() end
        self:Refresh()
        if self._hovered and self:GetScript("OnEnter") then self:GetScript("OnEnter")(self) end
    end)
    tool:SetScript("OnEnter", function(self)
        panel._hoverToolsShown = true
        self._hovered = true
        self:Refresh()
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Minimap Underlay", 1, 1, 1)
        GameTooltip:AddLine(Underlay.IsEnabled() and "On: Blizzard's minimap shows under the radar. Click to turn off."
            or "Off: click to show Blizzard's minimap under the radar.", .7, .8, .8, true)
        GameTooltip:AddLine(Underlay.Shape() == "circle"
            and "Shape: Circle, fits the range ring. Right-click for Square."
            or "Shape: Square, fills the face. Right-click for Circle.", .7, .8, .8, true)
        GameTooltip:Show()
    end)
    tool:SetScript("OnLeave", function(self)
        self._hovered = false
        self:Refresh()
        if GameTooltip then GameTooltip:Hide() end
        local leave = panel.field:GetScript("OnLeave")
        if leave then leave(panel.field) end
    end)
    local mirror
    for _, other in ipairs(panel.hoverTools) do
        if other.toolID == "eye" then mirror = other; break end
    end
    if mirror then
        tool:SetShown(mirror:IsShown())
        mirror:HookScript("OnShow", function() tool:Show() end)
        mirror:HookScript("OnHide", function() tool:Hide() end)
    else
        tool:Hide()
    end
    if not hooked then
        hooked = true
        -- The Minimap must not vanish with a hidden radar: give it back.
        panel:HookScript("OnHide", function() if active then Release(true, "radar hidden") end end)
        panel:HookScript("OnShow", function()
            if released then Trace("radar shown: borrow allowed again") end
            released = false
        end)
    end
    tool:Refresh()
    return tool
end

function Underlay.GetTool() return tool end

-- Events --------------------------------------------------------------------

local bus = addon.Bus
if bus then
    local function Invalidate()
        state.key, state.radii = nil, nil
    end
    bus.On("MINIMAP_UPDATE_ZOOM", function()
        if not active then return end
        local map = Map()
        -- Someone else zoomed: put ours back, at most once a second.
        local now = Now()
        if state.zoom and map and map:GetZoom() ~= state.zoom and now - lastZoomFix >= 1 then
            lastZoomFix = now
            Trace("zoom changed outside to %s", tostring(map:GetZoom()))
            Invalidate()
        elseif not state.zoom then
            Invalidate()
        end
    end)
    bus.On("ZONE_CHANGED_INDOORS", Invalidate)
    -- Blizzard re-lays its HUD out on these; the hold is checked once after,
    -- and only a hold that really broke counts as drift.
    local function Verify(event)
        if not active then return end
        Invalidate()
        local map, panel = Map(), CurrentPanel()
        if map and panel and panel.field and not Held(map, panel) then Drift(tostring(event)) end
    end
    bus.On("UI_SCALE_CHANGED", Verify)
    bus.On("DISPLAY_SIZE_CHANGED", Verify)
    bus.On("EDIT_MODE_LAYOUTS_UPDATED", Verify)
    bus.On("ZONE_CHANGED_NEW_AREA", Verify)
    -- Loading screens: check once the world has settled.
    bus.On("PLAYER_ENTERING_WORLD", function()
        Invalidate()
        if not After(1, function() Verify("PLAYER_ENTERING_WORLD") end) then Verify("PLAYER_ENTERING_WORLD") end
    end)
    bus.On("CVAR_UPDATE", function(_, name, value)
        if not (active and snapshot) then return end
        if name == "rotateMinimap" or name == "ROTATE_MINIMAP" then
            -- Our own write echoes back (maybe a frame later): not the player.
            local now = value ~= nil and tostring(value) or GetCVar("rotateMinimap")
            if now == written.rotateMinimap then return end
            -- The player changed Rotate Minimap: keep it as the value to restore.
            snapshot.rotate = now
            Invalidate()
        end
    end)
    local function AfterCombat()
        if not pending then return end
        if active and not Underlay.IsEnabled() then Release(true, "turned off in combat")
        else
            pending = false
            Trace("combat over: re-applying")
            Refresh(false)
        end
        if pending and C_Timer and C_Timer.After then C_Timer.After(1, AfterCombat) end
    end
    bus.On("PLAYER_REGEN_ENABLED", AfterCombat)
    -- Saved CVars go back to the player's own values at logout.
    bus.On("LOGOUT", function()
        if not (active and snapshot) then return end
        if snapshot.zoomOut then SetCVar("minimapZoom", snapshot.zoomOut) end
        if snapshot.zoomIn then SetCVar("minimapInsideZoom", snapshot.zoomIn) end
        RestoreRotation(snapshot)
    end)
end

do
    local registry = _G.EventRegistry
    if type(registry) == "table" and type(registry.RegisterCallback) == "function" then
        pcall(registry.RegisterCallback, registry, "EditMode.Enter", function() Underlay.OnEditMode(true) end, Underlay)
        pcall(registry.RegisterCallback, registry, "EditMode.Exit", function() Underlay.OnEditMode(false) end, Underlay)
    end
end

return Underlay
