-- Vantage/Core/Util.lua
-- Shared helpers + the private addon namespace.
-- Every Vantage file starts with this line; `Vantage` is one table shared across the addon.
local addonName, Vantage = ...

Vantage.name = addonName
Vantage.version = "0.11.0"

-- ---------------------------------------------------------------------------
-- Output
-- ---------------------------------------------------------------------------
local PREFIX = "|cff66ccffVantage|r: "

function Vantage:Print(...)
    print(PREFIX .. string.join(" ", tostringall(...)))
end

-- Only prints when the `debug` setting is on (set via /vantage debug).
function Vantage:Debug(...)
    if self.db and self.db.debug then
        print("|cff888888Vantage[dbg]|r: " .. string.join(" ", tostringall(...)))
    end
end

-- ---------------------------------------------------------------------------
-- Color palette (r, g, b in 0..1). One place to retheme the whole addon.
-- ---------------------------------------------------------------------------
Vantage.colors = {
    kick      = { 1.00, 0.82, 0.10 }, -- gold: "INTERRUPT NOW"
    kickDown  = { 0.55, 0.55, 0.60 }, -- muted: interruptible, but your kick is on CD
    locked    = { 0.85, 0.20, 0.20 }, -- red: uninterruptible (padlock)
    cast      = { 0.95, 0.65, 0.10 }, -- normal enemy cast
    channel   = { 0.10, 0.75, 1.00 }, -- enemy channel
    unknown   = { 0.70, 0.70, 0.70 }, -- cast we have no intel on
    kicked    = { 0.18, 0.64, 0.52 }, -- teal: outcome flash — the cast was stopped
    missed    = { 0.89, 0.36, 0.31 }, -- red: outcome flash — completed while your stop was ready
    threatOK  = { 0.20, 0.80, 0.25 }, -- you are securely tanking (tank mode)
    threatWarn= { 0.95, 0.75, 0.10 }, -- climbing / near pull
    threatBad = { 0.90, 0.20, 0.20 }, -- you pulled aggro / tank lost it
    -- group aggro BAR colors (the Plater-style "whose problem is this?" scheme)
    aggroAlarm= { 1.00, 0.25, 0.15 }, -- it's coming for YOU (dps) / you lost it (tank)
    aggroCalm = { 0.38, 0.44, 0.58 }, -- someone else's problem: COOL slate — calm must
                                      -- leave the red family entirely, or it blurs into
                                      -- alarm in dungeon lighting (hue > brightness)
    aggroSafe = { 0.28, 0.72, 0.35 }, -- tank mode: safely on you
}

-- Accent themes: the "go" color worn by the cue glow, the INTERRUPT label,
-- the kickable-cast bar, and the target outline. Every consumer reads it via
-- RGB("kick"), so remapping here re-themes the whole addon in one move.
-- Red (padlock/locked) and the threat colors are SEMANTIC and never themed —
-- and no accent is allowed near red, so "go" can never impersonate "stop".
Vantage.accents = {
    gold   = { 1.00, 0.82, 0.10 },
    teal   = { 0.16, 0.78, 0.62 },
    violet = { 0.68, 0.45, 1.00 },
    ice    = { 0.55, 0.78, 1.00 },
}

-- Unpack a palette entry: local r,g,b = Vantage:RGB("kick")
function Vantage:RGB(key)
    if key == "kick" and self.db then
        local a = self.accents[self.db.accent]
        if a then return a[1], a[2], a[3] end
    end
    local c = self.colors[key]
    return c[1], c[2], c[3]
end

-- ---------------------------------------------------------------------------
-- Anonymous install identity + GUID helpers (used by the community intel layer).
--
-- InstallID is a random, one-time, account-wide token. It carries NO character
-- or realm info — its only job is to let the community collector count DISTINCT
-- contributors (so a spell needs several independent confirmers before it's
-- trusted) without ever identifying who you are. It lives in VantageLearnedDB
-- so it survives a settings reset, like the learned intel it accompanies.
-- ---------------------------------------------------------------------------
local function hashStr(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483648 end
    return h
end

local seeded = false
local function seedOnce()
    if seeded then return end
    seeded = true
    -- Fold the character GUID into the SEED (never the output): two installs
    -- created in the same second still diverge, but the token reveals nothing.
    -- math.randomseed faults on the 2.5.x client, and it isn't load-bearing here
    -- (WoW auto-seeds math.random per session; the UUID already has 122 random
    -- bits). Guard + pcall it so a bad randomseed can NEVER take down InstallID —
    -- which would otherwise error the entire /vantage contribute flow.
    if type(math.randomseed) == "function" then
        local t   = (time and time()) or 0
        local gt  = (GetTime and math.floor(GetTime() * 1000)) or 0
        local g   = (UnitGUID and UnitGUID("player")) or ""
        pcall(math.randomseed, (t + gt + hashStr(g)) % 2147483648)
    end
end

local function newUUID()
    seedOnce()
    return ("xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"):gsub("[xy]", function(c)
        local v = (c == "x") and math.random(0, 15) or math.random(8, 11)
        return string.format("%x", v)
    end)
end

function Vantage:InstallID()
    if type(VantageLearnedDB) ~= "table" then VantageLearnedDB = {} end
    if not VantageLearnedDB.uuid then VantageLearnedDB.uuid = newUUID() end
    return VantageLearnedDB.uuid
end

-- Pull the creatureID out of a unit GUID (Creature-0-srv-inst-zone-<ID>-spawn).
-- This is the cross-check anchor: the collector can verify a submitted spell is
-- actually cast by this NPC, and in the submitted zone. Returns nil for players,
-- pets we can't map, or the simplified GUIDs used in tests.
function Vantage:NpcID(guid)
    if type(guid) ~= "string" then return nil end
    local parts = {}
    for seg in guid:gmatch("[^-]+") do parts[#parts + 1] = seg end
    local kind, id = parts[1], parts[6]
    if id and (kind == "Creature" or kind == "Vehicle") then
        return tonumber(id)
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Media. bar/glow are shipped TGAs (Media/); WHITE is a stock 8x8 solid.
-- Paths are built from the real folder name so a renamed install still works.
-- ---------------------------------------------------------------------------
local MEDIA = "Interface\\AddOns\\" .. addonName .. "\\Media\\"

Vantage.WHITE = "Interface\\Buttons\\WHITE8x8"
Vantage.BAR   = MEDIA .. "bar"    -- smooth vertical-gradient statusbar fill
Vantage.GLOW  = MEDIA .. "glow"   -- soft radial glow (halo / target glow / shadow)
Vantage.QUESTION_ICON = 134400    -- INV_Misc_QuestionMark

-- The statusbar fill every bar wears, per db.barTexture ("gradient" | "flat").
-- Flat is WHITE + the bar's own color: the modern, minimal look.
function Vantage:BarTex()
    return (self.db and self.db.barTexture == "flat") and self.WHITE or self.BAR
end

-- ---------------------------------------------------------------------------
-- Fonts. All text goes through Vantage:SetFont so the face (db.font) and the
-- treatment (db.fontStyle: outline | clean | thick) apply everywhere at once.
-- "clean" trades the outline for a dark drop shadow — reads less chunky at
-- nameplate sizes. Faces are the four fonts every client ships.
-- ---------------------------------------------------------------------------
Vantage.fonts = {
    { key = "friz",     label = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
    { key = "arial",    label = "Arial Narrow",  path = "Fonts\\ARIALN.TTF" },
    { key = "skurri",   label = "Skurri",        path = "Fonts\\skurri.ttf" },
    { key = "morpheus", label = "Morpheus",      path = "Fonts\\MORPHEUS.ttf" },
}

function Vantage:Font()
    local want = self.db and self.db.font
    for _, f in ipairs(self.fonts) do
        if f.key == want then return f.path end
    end
    return STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

function Vantage:FontFlags()
    local s = self.db and self.db.fontStyle
    if s == "clean" then return "" end
    if s == "thick" then return "THICKOUTLINE" end
    return "OUTLINE"
end

-- Apply face + style to a FontString. flagsOverride pins the treatment where
-- it's structural (the big cue label stays THICK regardless of style).
function Vantage:SetFont(fs, size, flagsOverride)
    fs:SetFont(self:Font(), size, flagsOverride or self:FontFlags())
    if fs.SetShadowColor then
        local clean = (self.db and self.db.fontStyle) == "clean" and not flagsOverride
        fs:SetShadowColor(0, 0, 0, clean and 0.9 or 0)
        fs:SetShadowOffset(1, -1)
    end
end

-- ---------------------------------------------------------------------------
-- Cue alert sound, per db.cueSound. Numeric fallbacks are the stable classic
-- sound-kit IDs, so a missing SOUNDKIT constant can't silence the cue.
-- ---------------------------------------------------------------------------
Vantage.sounds = {
    { key = "raid",  label = "Raid warning", kit = function() return (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959 end },
    { key = "ready", label = "Ready check",  kit = function() return (SOUNDKIT and SOUNDKIT.READY_CHECK) or 8960 end },
    { key = "bell",  label = "Alarm bell",   kit = function() return (SOUNDKIT and SOUNDKIT.ALARM_CLOCK_WARNING_3) or 12867 end },
}

function Vantage:CueSound()
    local want = self.db and self.db.cueSound
    for _, s in ipairs(self.sounds) do
        if s.key == want then return s.kit() end
    end
    return self.sounds[1].kit()
end

-- ---------------------------------------------------------------------------
-- Crisp 1px border from four edge textures (reads cleaner than a Backdrop at
-- 1px on tiny nameplate-sized frames). Edges sit 1px OUTSIDE the frame. The
-- textures are WHITE + vertex color, so :SetColor() genuinely tints them
-- (a color-texture base would multiply to black).
-- ---------------------------------------------------------------------------
function Vantage:CreateBorder(f)
    local edges = {}
    for i = 1, 4 do
        local t = f:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetTexture(Vantage.WHITE)
        t:SetVertexColor(0, 0, 0, 1)
        edges[i] = t
    end
    local top, bottom, left, right = edges[1], edges[2], edges[3], edges[4]
    top:SetPoint("TOPLEFT", f, -1, 1);         top:SetPoint("TOPRIGHT", f, 1, 1);         top:SetHeight(1)
    bottom:SetPoint("BOTTOMLEFT", f, -1, -1);  bottom:SetPoint("BOTTOMRIGHT", f, 1, -1);  bottom:SetHeight(1)
    left:SetPoint("TOPLEFT", f, -1, 1);        left:SetPoint("BOTTOMLEFT", f, -1, -1);    left:SetWidth(1)
    right:SetPoint("TOPRIGHT", f, 1, 1);       right:SetPoint("BOTTOMRIGHT", f, 1, -1);   right:SetWidth(1)

    local b = { edges = edges }
    function b:SetColor(r, g, bl, a)
        for i = 1, 4 do edges[i]:SetVertexColor(r, g, bl, a or 1) end
    end
    function b:Show() for i = 1, 4 do edges[i]:Show() end end
    function b:Hide() for i = 1, 4 do edges[i]:Hide() end end
    return b
end
