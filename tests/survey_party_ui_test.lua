local settings = {}
local counts = { configure = 0, sighting = 0, stop = 0, saved = 0, deleted = 0,
    atlas = 0, coverage = 0 }
local denseCoverage = false
local reports = {
    { sender = "Friend-Realm", name = "A Rare", age = 12,
        evidence = "group-report" },
}
local saves = {}
local function Node(kind)
    local object = { kind = kind, shown = true, scripts = {}, enabled = true }
    setmetatable(object, { __index = {
        SetSize = function(self, width, height) self.width, self.height = width, height end,
        SetPoint = function(self, ...) self.point = { ... } end,
        SetFrameStrata = function() end,
        SetClampedToScreen = function() end,
        EnableMouse = function() end,
        SetBackdrop = function() end,
        SetBackdropColor = function() end,
        SetBackdropBorderColor = function() end,
        SetTextInsets = function() end,
        SetAutoFocus = function() end,
        SetMaxLetters = function() end,
        SetFont = function() end,
        SetJustifyH = function() end,
        SetWordWrap = function() end,
        ClearFocus = function() end,
        SetTextColor = function() end,
        SetText = function(self, text) self.text = text end,
        GetText = function(self) return self.text end,
        SetChecked = function(self, value) self.checked = value end,
        GetChecked = function(self) return self.checked end,
        SetEnabled = function(self, value) self.enabled = value end,
        SetShown = function(self, value) self.shown = value end,
        IsShown = function(self) return self.shown end,
        Show = function(self)
            self.shown = true
            if self.scripts.OnShow then self.scripts.OnShow(self) end
        end,
        Hide = function(self) self.shown = false end,
        SetScript = function(self, name, callback) self.scripts[name] = callback end,
        CreateFontString = function() return Node("FontString") end,
        CreateTexture = function() return Node("Texture") end,
        SetTexture = function(self, value) self.texture = value end,
        SetTexCoord = function(self, ...) self.texCoord = { ... } end,
        SetVertexColor = function(self, ...) self.vertexColor = { ... } end,
        LockHighlight = function(self) self.selected = true end,
        UnlockHighlight = function(self) self.selected = false end,
    } })
    return object
end

UIParent = Node("Frame")
UISpecialFrames = {}
STANDARD_TEXT_FONT = "font"
CreateFrame = function(kind, name)
    local frame = Node(kind)
    if name then _G[name] = frame end
    return frame
end
C_Map = { GetBestMapForUnit = function() return 100 end }
GetServerTime = function() return 5000 end

local fontStyle = {}
assert(loadfile("UI/Style.lua"))("VignetteRadar", fontStyle)
local addon = {
    GetSettings = function() return settings end,
    VignetteRadarStyle = { SetFont = fontStyle.VignetteRadarStyle.SetFont, Color = function() return .5, .4, 1 end },
    VignetteRadarControls = {
        Button = function(_, title, width, height)
            local button = Node("Button")
            button:SetSize(width, height)
            button:SetText(title)
            return button
        end,
        Checkbox = function() return Node("CheckButton") end,
        PopupSurface = function() end,
        RefreshPopupSurface = function() end,
    },
    VignetteRadarSurveyReplay = {
        GetCoverage = function(_, shared)
            assert(shared == false or shared == true)
            if denseCoverage then
                local cells = {}
                for row = 0, 39 do
                    for column = 0, 39 do
                        cells[column .. ":" .. row] = true
                    end
                end
                return cells, 1600, 1
            end
            return { ["4:4"] = true, ["5:4"] = true }, 2, .2
        end,
        GetCellSize = function() return .025 end,
        GetTimeline = function()
            return {
                { kind = "appeared", name = "A Rare", at = 4990,
                    point = { mapID = 100, mapX = .2, mapY = .3 } },
                { kind = "vanished", name = "A Rare", at = 4991,
                    point = { mapID = 100, mapX = .2, mapY = .3 } },
                { kind = "movement", at = 4992,
                    point = { mapID = 100, mapX = .21, mapY = .3 } },
            }
        end,
        SaveReplay = function(name, epoch)
            assert(name == "Rare Route" and epoch == 5000)
            counts.saved = counts.saved + 1
            saves[#saves + 1] = { name = name, events = {
                { name = "A Rare", kind = "appeared", at = 4990,
                    point = { mapID = 100, mapX = .2, mapY = .3 } },
            } }
            return true
        end,
        GetSavedReplays = function() return saves end,
        DeleteReplay = function(index)
            counts.deleted = counts.deleted + 1
            table.remove(saves, index)
            return true
        end,
    },
    VignetteRadarFeatureRuntime = {
        Configure = function() counts.configure = counts.configure + 1 end,
        GetParty = function()
            return { GetReports = function() return reports end }
        end,
        ShareSighting = function(record, requested)
            assert(requested == true and record.identity == "npc:42")
            counts.sighting = counts.sighting + 1
            return true
        end,
        ShareStop = function(record, requested)
            assert(requested == true and record.identity == "quest:12")
            counts.stop = counts.stop + 1
            return true
        end,
    },
    VignetteRadarAtlas = {
        SetData = function(mapID, entries)
            assert(mapID == 100 and #entries > 0 and #entries <= 128)
            assert(entries[1].evidence == "observed")
            if entries[1].coverage then
                assert(entries[1].source == "survey"
                    and entries[1].title == "Observed Survey Coverage"
                    and not entries[1].historical)
                counts.coverage = counts.coverage + 1
            else
                assert(entries[1].historical)
            end
            counts.atlas = counts.atlas + 1
        end,
        Open = function() return true end,
    },
}
assert(loadfile("UI/IconButton.lua"))("VignetteRadar", addon)
assert(loadfile("UI/SurveyParty.lua"))("VignetteRadar", addon)
local api = addon.VignetteRadarSurveyParty
assert(api.Open() and api.IsOpen())
local panel = VignetteRadarSurveyPartyPanel
assert(panel.width == 400 and panel.height == 488)
assert(panel.pages.Survey.shown and not panel.pages.Party.shown)
assert(panel.pages.Survey.coverage.text:find("2 Cells Visited", 1, true))
assert(panel.pages.Survey.viewCoverage.enabled and counts.atlas == 0)
panel.pages.Survey.viewCoverage.scripts.OnClick()
assert(counts.coverage == 1 and counts.atlas == 1)
assert(not api.IsOpen())
assert(api.Open())
panel.pages.Survey.surveyBox.checked = true
panel.pages.Survey.surveyBox.scripts.OnClick(panel.pages.Survey.surveyBox)
assert(settings.vignetteRadarSurveying and counts.configure == 1)
panel.pages.Survey.sizes[1].scripts.OnClick()
assert(settings.vignetteRadarSurveyCellSize == .02 and counts.configure == 2)
panel.tabs.Replay.scripts.OnClick()
assert(panel.pages.Replay.shown and panel.pages.Replay.timeline.text:find("3 Signals", 1, true))
panel.pages.Replay.viewSession.scripts.OnClick()
assert(counts.atlas == 2)
assert(not api.IsOpen(), "viewing a replay must reveal the Atlas")
assert(api.Open())
panel.pages.Replay.input:SetText("Rare Route")
panel.pages.Replay.save.scripts.OnClick()
assert(counts.saved == 1 and panel.pages.Replay.saved[1].name.text == "Rare Route")
panel.pages.Replay.saved[1].view.scripts.OnClick()
assert(counts.atlas == 3)
panel.pages.Replay.saved[1].delete.scripts.OnClick()
assert(counts.deleted == 1 and #saves == 0)
panel.tabs.Party.scripts.OnClick()
assert(panel.pages.Party.shown and panel.pages.Party.report[1].label.text:find("Friend%-Realm"))
assert(panel.pages.Party.report[1].label.text:find("12 sec", 1, true))
assert(panel.pages.Party.shareSighting.enabled == false)
api.SetShareTargets({ identity = "npc:42" }, { identity = "quest:12" })
panel.pages.Party.receive[2].scripts.OnClick()
assert(settings.vignetteRadarPartyHunt.receive == "party")
panel.pages.Party.sightingBox.checked = true
panel.pages.Party.sightingBox.scripts.OnClick(panel.pages.Party.sightingBox)
panel.pages.Party.stopBox.checked = true
panel.pages.Party.stopBox.scripts.OnClick(panel.pages.Party.stopBox)
assert(counts.sighting == 0 and counts.stop == 0,
    "settings changes must not broadcast")
assert(panel.pages.Party.shareSighting.enabled and panel.pages.Party.shareStop.enabled)
panel.pages.Party.shareSighting.scripts.OnClick()
panel.pages.Party.shareStop.scripts.OnClick()
assert(counts.sighting == 1 and counts.stop == 1)
panel.pages.Party.report[1].ignore.scripts.OnClick()
assert(settings.vignetteRadarPartyHunt.ignored["friend-realm"])
assert(panel.pages.Party.report[1].label.text == "")
assert(panel.pages.Party.note.text:find("never change your route", 1, true))
denseCoverage = true
assert(api.Open())
panel.tabs.Survey.scripts.OnClick()
panel.pages.Survey.viewCoverage.scripts.OnClick()
assert(counts.coverage == 2 and counts.atlas == 4,
    "dense coverage must remain a bounded click-only snapshot")
api.Close()
assert(not api.IsOpen())
print("survey, replay, and party UI tests passed")
