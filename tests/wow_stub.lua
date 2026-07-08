-- tests/wow_stub.lua
--
-- A headless mock of the slice of the WoW 2.5.x API that Vantage touches, so the
-- whole addon can be loaded and driven under plain Lua 5.1 (via lupa) — the
-- closest thing to an in-game smoke test that runs in CI.
--
-- Design rule: NO magic fallbacks. Frames use explicit method tables; a method
-- or global we forgot surfaces as "attempt to call nil", which is exactly the
-- signal we want — then we either add it here (client has it) or we found a
-- real bug (client doesn't).
--
-- The `Harness` global is the control panel: fake clock, unit state, cooldown
-- and range maps, CLEU payload, event firing, timer/OnUpdate pumps.

Harness = {
    now = 10000,          -- GetTime() clock
    units = {},           -- token -> unit state table
    alias = {},           -- token -> token ("target" -> "nameplate1")
    cooldowns = {},       -- spell name -> {start, duration}
    range = {},           -- spell name -> 0|1 (default 1 = in range)
    cleu = {},            -- payload for CombatLogGetCurrentEventInfo
    timers = {},          -- {at, fn, period}
    frames = {},          -- every created frame (for the OnUpdate pump)
    events = {},          -- event -> {frame, ...}
    printed = {},         -- captured print() lines
    sounds = 0,           -- PlaySound call count
    screenshots = 0,
}

-- ---------------------------------------------------------------------------
-- Lua-side WoW-isms
-- ---------------------------------------------------------------------------
date = os.date
time = os.time

function GetTime() return Harness.now end

function tostringall(...)
    local n, out = select("#", ...), {}
    for i = 1, n do out[i] = tostring((select(i, ...))) end
    return unpack(out, 1, n)
end

function string.join(sep, ...) return table.concat({ ... }, sep) end

function wipe(t)
    for k in pairs(t) do t[k] = nil end
    return t
end

print_real = print
function print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    Harness.printed[#Harness.printed + 1] = table.concat(parts, " ")
end

function hooksecurefunc(a, b, c)
    if type(a) == "table" then
        local orig = a[b]
        rawset(a, b, function(...) local r = orig(...); c(...); return r end)
    else
        local orig = _G[a]
        _G[a] = function(...) local r = orig(...); b(...); return r end
    end
end

-- ---------------------------------------------------------------------------
-- Widget factory
-- ---------------------------------------------------------------------------
local function mkRegion(kind)
    local r = { __kind = kind, __shown = true, __text = "", __alpha = 1 }
    return r
end

local Region = {}  -- shared by textures + fontstrings
function Region.Show(self) self.__shown = true end
function Region.Hide(self) self.__shown = false end
function Region.IsShown(self) return self.__shown end
function Region.SetShown(self, s) self.__shown = not not s end
function Region.SetPoint(self, point, rel, relPoint, x, y)
    -- record anchors so scenarios can assert WHAT a frame hangs off
    self.__anchors = self.__anchors or {}
    self.__anchors[#self.__anchors + 1] =
        { point = point, rel = rel, relPoint = relPoint, x = x, y = y }
end
function Region.ClearAllPoints(self) self.__anchors = nil end
function Region.SetAllPoints() end
function Region.SetSize(self, w, h) self.__w, self.__h = w, h end
function Region.SetWidth(self, w) self.__w = w end
function Region.SetHeight(self, h) self.__h = h end
function Region.GetWidth(self) return self.__w or 0 end
function Region.SetAlpha(self, a) self.__alpha = a end
function Region.SetParent() end
function Region.SetDrawLayer() end
-- texture-ish
function Region.SetTexture(self, t) self.__tex = t end
function Region.SetColorTexture() end
function Region.SetVertexColor(self, r, g, b, a) self.__vr, self.__vg, self.__vb, self.__va = r, g, b, a end
function Region.SetTexCoord() end
function Region.SetBlendMode() end
function Region.SetGradient() end
function Region.SetRotation() end
-- fontstring-ish
function Region.SetFont(self, f, size, flags) self.__font = { f, size, flags } end
function Region.GetFont(self)
    local f = self.__font or { "Fonts\\FRIZQT__.TTF", 10, "" }
    return f[1], f[2], f[3]
end
function Region.SetFontObject() end
function Region.SetText(self, t) self.__text = t or "" end
function Region.GetText(self) return self.__text end
function Region.SetFormattedText(self, fmt, ...) self.__text = string.format(fmt, ...) end
function Region.SetTextColor(self, r, g, b) self.__tr, self.__tg, self.__tb = r, g, b end
function Region.SetJustifyH() end
function Region.SetWordWrap() end
function Region.SetSpacing() end
function Region.GetStringWidth(self) return #(self.__text or "") * 6 end

local RegionMT = { __index = Region }

local function newRegion(kind)
    return setmetatable(mkRegion(kind), RegionMT)
end

-- Animations
local Anim = {}
function Anim.SetFromAlpha() end
function Anim.SetToAlpha() end
function Anim.SetDuration() end
function Anim.SetSmoothing() end
function Anim.SetOrder() end
function Anim.SetScale() end
local AnimMT = { __index = Anim }

local AnimGroup = {}
function AnimGroup.CreateAnimation() return setmetatable({}, AnimMT) end
function AnimGroup.SetLooping() end
function AnimGroup.Play(self) self.__playing = true end
function AnimGroup.Stop(self) self.__playing = false end
function AnimGroup.IsPlaying(self) return self.__playing end
local AnimGroupMT = { __index = AnimGroup }

-- Frames
local Frame = {}
-- unlike plain regions, frames fire OnShow/OnHide on visibility TRANSITIONS
function Frame.Show(self)
    if not self.__shown then
        self.__shown = true
        local fn = self.__scripts and self.__scripts.OnShow
        if fn then fn(self) end
    end
end
function Frame.Hide(self)
    if self.__shown then
        self.__shown = false
        local fn = self.__scripts and self.__scripts.OnHide
        if fn then fn(self) end
    end
end
Frame.IsShown = Region.IsShown
function Frame.SetShown(self, s)
    if s then self:Show() else self:Hide() end
end
Frame.SetPoint = Region.SetPoint
Frame.ClearAllPoints = Region.ClearAllPoints
Frame.SetAllPoints = Region.SetAllPoints
Frame.SetParent = Region.SetParent
Frame.SetAlpha = Region.SetAlpha
function Frame.SetSize(self, w, h) self.__w, self.__h = w, h end
function Frame.SetWidth(self, w) self.__w = w end
function Frame.SetHeight(self, h) self.__h = h end
function Frame.GetWidth(self) return self.__w or 0 end
function Frame.GetHeight(self) return self.__h or 0 end
function Frame.SetScale(self, s) self.__scale = s end
function Frame.GetScale(self) return self.__scale or 1 end
function Frame.SetFrameStrata() end
function Frame.SetFrameLevel(self, l) self.__lvl = l end
function Frame.GetFrameLevel(self) return self.__lvl or 1 end
function Frame.EnableMouse() end
function Frame.SetMovable() end
function Frame.RegisterForDrag() end
function Frame.SetClampedToScreen() end
function Frame.StartMoving() end
function Frame.StopMovingOrSizing() end
function Frame.IsForbidden() return false end
function Frame.GetName(self) return self.__name end

function Frame.CreateTexture(self)
    local r = newRegion("texture")
    self.__regions = self.__regions or {}
    self.__regions[#self.__regions + 1] = r
    return r
end
function Frame.CreateFontString(self)
    local r = newRegion("fontstring")
    self.__regions = self.__regions or {}
    self.__regions[#self.__regions + 1] = r
    return r
end
function Frame.GetRegions(self) return unpack(self.__regions or {}) end
function Frame.GetChildren(self) return unpack(self.__children or {}) end
function Frame.CreateAnimationGroup(self) return setmetatable({}, AnimGroupMT) end

function Frame.SetScript(self, ev, fn) self.__scripts[ev] = fn end
function Frame.GetScript(self, ev) return self.__scripts[ev] end
function Frame.HookScript(self, ev, fn)
    local prev = self.__scripts[ev]
    self.__scripts[ev] = prev and function(...) prev(...); fn(...) end or fn
end

function Frame.RegisterEvent(self, event)
    local list = Harness.events[event]
    if not list then list = {}; Harness.events[event] = list end
    list[#list + 1] = self
end
function Frame.UnregisterEvent() end

-- StatusBar
function Frame.SetMinMaxValues(self, lo, hi) self.__min, self.__max = lo, hi end
function Frame.GetMinMaxValues(self) return self.__min or 0, self.__max or 1 end
function Frame.SetStatusBarTexture(self, t) self.__bartex = self.__bartex or newRegion("texture"); self.__bartex:SetTexture(t) end
function Frame.GetStatusBarTexture(self) self.__bartex = self.__bartex or newRegion("texture"); return self.__bartex end
function Frame.SetStatusBarColor(self, r, g, b, a) self.__barcolor = { r, g, b, a } end
function Frame.SetValue(self, v)
    self.__value = v
    local fn = self.__scripts and self.__scripts.OnValueChanged
    if fn then fn(self, v) end
end
function Frame.GetValue(self) return self.__value or 0 end
function Frame.SetValueStep() end
function Frame.SetObeyStepOnDrag() end
function Frame.SetOrientation() end
function Frame.SetThumbTexture(self, t)
    self.__thumb = self.__thumb or newRegion("texture")
    self.__thumb:SetTexture(t)
end
function Frame.GetThumbTexture(self)
    self.__thumb = self.__thumb or newRegion("texture")
    return self.__thumb
end

-- CheckButton / Button
function Frame.SetChecked(self, c) self.__checked = not not c end
function Frame.GetChecked(self) return self.__checked end
Frame.SetText = Region.SetText
Frame.GetText = Region.GetText
function Frame.Click(self)
    local fn = self.__scripts.OnClick
    if fn then fn(self, "LeftButton") end
end

-- EditBox / ScrollFrame
function Frame.SetMultiLine() end
function Frame.SetMaxLetters() end
function Frame.SetAutoFocus() end
Frame.SetFontObject = Region.SetFontObject
function Frame.HighlightText() end
function Frame.SetFocus() end
function Frame.ClearFocus() end
function Frame.SetScrollChild() end

-- CastingBar mixin surface (2.5.5+): SetUnit(nil) detaches + hides
function Frame.SetUnit(self, unit)
    self.__unit = unit
    if not unit then self:Hide() end
end

-- Cooldown
function Frame.SetCooldown() end
function Frame.SetReverse() end
function Frame.SetHideCountdownNumbers() end
function Frame.SetDrawEdge() end
function Frame.Clear() end

-- Tooltip
function Frame.SetOwner() end
function Frame.AddLine() end

local FrameMT = { __index = Frame }

function CreateFrame(kind, name, parent, template)
    local f = setmetatable({
        __kind = kind, __name = name, __template = template,
        __shown = true, __scripts = {},
    }, FrameMT)
    Harness.frames[#Harness.frames + 1] = f
    if type(parent) == "table" then
        parent.__children = parent.__children or {}
        parent.__children[#parent.__children + 1] = f
    end
    if name then
        _G[name] = f
        if template and template:find("Slider") then
            _G[name .. "Low"] = newRegion("fontstring")
            _G[name .. "High"] = newRegion("fontstring")
            _G[name .. "Text"] = newRegion("fontstring")
        end
    end
    return f
end

UIParent = CreateFrame("Frame", "UIParent")
GameTooltip = CreateFrame("Frame", "GameTooltip")
ChatFontNormal = {}
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
NUM_PET_ACTION_SLOTS = 10
SOUNDKIT = { RAID_WARNING = 8959 }
SlashCmdList = {}

RAID_CLASS_COLORS = {}
for _, c in ipairs({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }) do
    RAID_CLASS_COLORS[c] = { r = 0.5, g = 0.5, b = 0.8, colorStr = "ff8080cc" }
end
DebuffTypeColor = {
    Magic = { r = 0.2, g = 0.6, b = 1.0 }, Curse = { r = 0.6, g = 0, b = 1 },
    Disease = { r = 0.6, g = 0.4, b = 0 }, Poison = { r = 0, g = 0.6, b = 0 },
    none = { r = 0.8, g = 0, b = 0 },
}

function GetQuestDifficultyColor() return { r = 1, g = 0.82, b = 0 } end
function PlaySound() Harness.sounds = Harness.sounds + 1 end
function Screenshot() Harness.screenshots = Harness.screenshots + 1 end
function InterfaceOptions_AddCategory() end
function InterfaceOptionsFrame_OpenToCategory() end

function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton(info)
    local dd = Harness.__currentDD
    if dd then dd.__items = dd.__items or {}; dd.__items[#dd.__items + 1] = info end
end
function UIDropDownMenu_Initialize(dd, fn)
    Harness.__currentDD = dd
    fn()
    Harness.__currentDD = nil
end
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_SetText(dd, t) dd.__ddtext = t end

-- ---------------------------------------------------------------------------
-- Unit API (driven by Harness.units / Harness.alias)
-- ---------------------------------------------------------------------------
local function U(token)
    token = Harness.alias[token] or token
    return Harness.units[token], token
end

function UnitExists(t) return U(t) ~= nil end
function UnitName(t) local u = U(t); return u and u.name, u and u.realm end
function UnitClass(t) local u = U(t); return u and u.className or "?", u and u.class end
function UnitRace(t) local u = U(t); return "Orc", u and u.race or "Orc" end
function UnitFactionGroup() return "Horde" end
function UnitGUID(t) local u = U(t); return u and u.guid end
function UnitLevel(t) local u = U(t); return u and u.level or 70 end
function UnitIsPlayer(t) local u = U(t); return u and u.isPlayer or false end
function UnitIsDead(t) local u = U(t); return u and u.dead or false end
function UnitCanAttack(_, t) local u = U(t); return u and u.hostile or false end
function UnitIsUnit(a, b)
    local _, ra = U(a); local _, rb = U(b)
    return ra == rb
end
function UnitClassification(t) local u = U(t); return u and u.classification or "normal" end
function UnitCreatureType(t) local u = U(t); return u and u.creatureType or "Humanoid" end
function UnitSelectionColor() return 1, 0.2, 0.2, 1 end
function UnitHealth(t) local u = U(t); return u and u.health or 100 end
function UnitHealthMax(t) local u = U(t); return u and u.healthMax or 100 end
function UnitPowerType(t) local u = U(t); return u and u.powerType or 0, "MANA" end
function UnitPower(t) return 50 end
function UnitPowerMax(t) local u = U(t); return u and u.powerMax or 100 end
function UnitIsFriend(_, t) local u = U(t); return u and not u.hostile end
function UnitAffectingCombat(t) local u = U(t); return (u and u.inCombat) or false end
function UnitIsTapDenied() return false end

-- threat: driven by unit.threat = {isTanking, status, pct} (nil = no table)
function UnitDetailedThreatSituation(_, t)
    local u = U(t)
    local th = u and u.threat
    if not th then return nil end
    return th.isTanking or false, th.status, th.pct
end

function UnitCastingInfo(t)
    local u = U(t)
    local c = u and u.casting
    if not c or c.channel then return nil end
    return c.name, c.name, c.icon or 136207, c.startMS, c.endMS, false, nil, c.notInterruptible or false, c.spellID
end

function UnitChannelInfo(t)
    local u = U(t)
    local c = u and u.casting
    if not c or not c.channel then return nil end
    return c.name, c.name, c.icon or 136207, c.startMS, c.endMS, false, false, c.spellID
end

function UnitAura(t, i, filter)
    local u = U(t)
    local a = u and u.auras and u.auras[i]
    if not a then return nil end
    return a.name, a.icon or 136207, a.count or 1, a.debuffType, a.duration or 18,
           a.expirationTime or (Harness.now + 12), a.source or "player", false, false, a.spellID or 589
end

-- ---------------------------------------------------------------------------
-- Spells, items, combat
-- ---------------------------------------------------------------------------
function GetSpellCooldown(name)
    local cd = Harness.cooldowns[name]
    if not cd then return nil end
    return cd[1], cd[2], 1
end

function GetSpellInfo(id) return "Spell" .. tostring(id), nil, 136207 end

function IsSpellInRange(name, unit)
    local r = Harness.range[name]
    if r == nil then return 1 end
    return r
end

function GetShapeshiftForm() return Harness.form or 0 end
function GetInventoryItemLink() return nil end
function GetItemInfo() return nil end
function GetComboPoints() return 0 end
function GetPetActionInfo() return nil end
function GetPetActionCooldown() return 0, 0, 1 end

function CombatLogGetCurrentEventInfo()
    return unpack(Harness.cleu, 1, 20)
end

-- ---------------------------------------------------------------------------
-- World / misc
-- ---------------------------------------------------------------------------
function GetRealmName() return "Dreamscythe" end
function GetRealZoneText() return "Shadow Labyrinth" end

-- WoW ships a bit library on 2.5.x; plain Lua 5.1 here, so a pure-Lua band
bit = bit or {}
bit.band = bit.band or function(a, b)
    local r, p = 0, 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then r = r + p end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        p = p * 2
    end
    return r
end

function GetPlayerInfoByGUID(guid)
    return "Mage", "MAGE" -- localizedClass, englishClass, ...
end
function GetZoneText() return "Shadow Labyrinth" end
function GetInstanceInfo() return "Shadow Labyrinth", "party", 2, "Heroic", 5, 0, false, 555, 5 end
function IsInInstance() return true, "party" end
function IsInRaid() return false end
function IsInGroup() return Harness.inGroup or false end
function GetNumGroupMembers() return Harness.groupSize or 0 end
function InCombatLockdown() return false end
function LoggingCombat() end

C_NamePlate = {
    GetNamePlateForUnit = function(token)
        local u = U(token)
        return u and u.plate
    end,
    GetNamePlates = function()
        local out = {}
        for token, u in pairs(Harness.units) do
            if u.plate then out[#out + 1] = u.plate end
        end
        return out
    end,
}

C_Timer = {
    After = function(d, fn)
        Harness.timers[#Harness.timers + 1] = { at = Harness.now + d, fn = fn }
    end,
    NewTicker = function(d, fn)
        local t = { at = Harness.now + d, fn = fn, period = d }
        Harness.timers[#Harness.timers + 1] = t
        return { Cancel = function() t.dead = true end }
    end,
}

-- ---------------------------------------------------------------------------
-- Harness controls
-- ---------------------------------------------------------------------------

-- a plate object shaped like a 2.5.x nameplate (what Skin/Nameplates reach into)
-- Shaped like the 2.5.5+ Anniversary client's NamePlateUnitFrameTemplate
-- (verified against Blizzard_NamePlates.xml): the health bar lives inside
-- HealthBarsContainer next to the rounded border art, uf.healthBar is the
-- Lua-side alias, and the plate cast bar is LOWERCASE castBar.
function Harness.MakePlate()
    local plate = CreateFrame("Frame")
    local uf = CreateFrame("Frame", nil, plate)
    local container = CreateFrame("Frame", nil, uf)
    container:SetHeight(11) -- the client's default bar height (restore target)
    uf.HealthBarsContainer = container
    container.border = CreateFrame("Frame", nil, container) -- Nameplate-Border art, strata HIGH
    local hb = CreateFrame("StatusBar", nil, container)
    hb:SetWidth(124)
    hb:SetMinMaxValues(0, 100)
    hb.background = hb:CreateTexture() -- stock grey fill behind the bar
    container.healthBar = hb
    uf.healthBar = hb -- the alias the addon (and Blizzard code) reads
    uf.name = uf:CreateFontString()
    uf.castBar = CreateFrame("StatusBar", nil, uf)
    uf.selectionHighlight = uf:CreateTexture()
    uf.LevelFrame = CreateFrame("Frame", nil, uf)
    uf.LevelFrame.levelText = uf.LevelFrame:CreateFontString()
    uf.LevelFrame.highLevelTexture = uf.LevelFrame:CreateTexture()
    uf.RaidTargetFrame = CreateFrame("Frame", nil, uf)
    plate.UnitFrame = uf
    return plate
end

function Harness.FireEvent(event, ...)
    local list = Harness.events[event]
    if not list then return end
    for i = 1, #list do
        local f = list[i]
        local fn = f.__scripts.OnEvent
        if fn then fn(f, event, ...) end
    end
end

function Harness.SetCLEU(...)
    wipe(Harness.cleu)
    local n = select("#", ...)
    for i = 1, n do Harness.cleu[i] = (select(i, ...)) end
end

-- advance the fake clock in small steps, pumping OnUpdate scripts and C_Timer
function Harness.Advance(total, step)
    step = step or 0.1
    local left = total
    while left > 0 do
        local dt = math.min(step, left)
        left = left - dt
        Harness.now = Harness.now + dt
        for i = 1, #Harness.frames do
            local f = Harness.frames[i]
            local fn = f.__scripts.OnUpdate
            if fn and f.__shown then fn(f, dt) end
        end
        for i = 1, #Harness.timers do
            local t = Harness.timers[i]
            if not t.dead and t.at and Harness.now >= t.at then
                if t.period then t.at = Harness.now + t.period else t.at = nil end
                t.fn()
            end
        end
    end
end

-- load one addon file the way WoW does: vararg (addonName, namespace)
function Harness.LoadAddonFile(path, ns)
    local fh = assert(io.open(path, "r"))
    local src = fh:read("*a")
    fh:close()
    local chunk, err = loadstring(src, "@" .. path)
    if not chunk then error(err, 0) end
    chunk("Vantage", ns)
end
