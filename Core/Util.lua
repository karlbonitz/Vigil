-- Vigil/Core/Util.lua
-- Shared helpers + the private addon namespace.
-- Every Vigil file starts with this line; `Vigil` is one table shared across the addon.
local addonName, Vigil = ...

Vigil.name = addonName
Vigil.version = "0.7.0"

-- ---------------------------------------------------------------------------
-- Output
-- ---------------------------------------------------------------------------
local PREFIX = "|cff66ccffVigil|r: "

function Vigil:Print(...)
    print(PREFIX .. string.join(" ", tostringall(...)))
end

-- Only prints when the `debug` setting is on (set via /vigil debug).
function Vigil:Debug(...)
    if self.db and self.db.debug then
        print("|cff888888Vigil[dbg]|r: " .. string.join(" ", tostringall(...)))
    end
end

-- ---------------------------------------------------------------------------
-- Color palette (r, g, b in 0..1). One place to retheme the whole addon.
-- ---------------------------------------------------------------------------
Vigil.colors = {
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
}

-- Accent themes: the "go" color worn by the cue glow, the INTERRUPT label,
-- the kickable-cast bar, and the target outline. Every consumer reads it via
-- RGB("kick"), so remapping here re-themes the whole addon in one move.
-- Red (padlock/locked) and the threat colors are SEMANTIC and never themed —
-- and no accent is allowed near red, so "go" can never impersonate "stop".
Vigil.accents = {
    gold   = { 1.00, 0.82, 0.10 },
    teal   = { 0.16, 0.78, 0.62 },
    violet = { 0.68, 0.45, 1.00 },
    ice    = { 0.55, 0.78, 1.00 },
}

-- Unpack a palette entry: local r,g,b = Vigil:RGB("kick")
function Vigil:RGB(key)
    if key == "kick" and self.db then
        local a = self.accents[self.db.accent]
        if a then return a[1], a[2], a[3] end
    end
    local c = self.colors[key]
    return c[1], c[2], c[3]
end

-- ---------------------------------------------------------------------------
-- Media. bar/glow are shipped TGAs (Media/); WHITE is a stock 8x8 solid.
-- Paths are built from the real folder name so a renamed install still works.
-- ---------------------------------------------------------------------------
local MEDIA = "Interface\\AddOns\\" .. addonName .. "\\Media\\"

Vigil.WHITE = "Interface\\Buttons\\WHITE8x8"
Vigil.BAR   = MEDIA .. "bar"    -- smooth vertical-gradient statusbar fill
Vigil.GLOW  = MEDIA .. "glow"   -- soft radial glow (halo / target glow / shadow)
Vigil.QUESTION_ICON = 134400    -- INV_Misc_QuestionMark

-- ---------------------------------------------------------------------------
-- Crisp 1px border from four edge textures (reads cleaner than a Backdrop at
-- 1px on tiny nameplate-sized frames). Edges sit 1px OUTSIDE the frame. The
-- textures are WHITE + vertex color, so :SetColor() genuinely tints them
-- (a color-texture base would multiply to black).
-- ---------------------------------------------------------------------------
function Vigil:CreateBorder(f)
    local edges = {}
    for i = 1, 4 do
        local t = f:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetTexture(Vigil.WHITE)
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
