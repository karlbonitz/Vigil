-- Vantage/Modules/Parse.lua
--
-- VANTAGE PARSE, phase 1: the in-game collector. Every enemy-cast decision the
-- cue engine makes becomes a row, and combat-log outcomes attach to it:
--
--   row = { t (epoch), z (zone), src (caster), sp/sid (spell), pvp,
--           tier ("ready"/"cd"/"aware"/"locked"/"unknown"),
--           win  (a kick window was shown to you),
--           tool (the interrupt Vantage offered),
--           out  ("int" interrupted / "done" completed / "stop" fizzled / nil open),
--           by   ("me"/"other", for out=="int"),
--           rx   (ms from cue shown -> YOUR interrupt landing),
--           miss (completed while your stop was ready — the headline stat),
--           wk   (you kicked a cast marked uninterruptible) }
--
-- This is the data Warcraft Logs can't show: not "how many interrupts did you
-- cast" but "how many casts did you LET THROUGH while your kick sat ready".
--
-- Storage: VantageParseDB.sessions (SavedVariables — flushes to disk on logout
-- or /reload). One session per login, oldest sessions pruned. Read-only and
-- cheap: rows only exist for casts Vantage already evaluated on visible plates.
--
-- PLUS the ROSTER (VantageParseDB.roster): a durable per-player profile of
-- every FRIENDLY player Vantage ever witnesses landing an interrupt — name,
-- class, total kicks (and how many while grouped with you), favorite tool,
-- first/last seen. Grows across sessions; /vantage roster to browse.
local addonName, Vantage = ...
local M = Vantage:NewModule("Parse")

local MAX_SESSIONS = 8     -- keep this many sessions in SavedVariables
local MAX_ROWS     = 4000  -- per-session row cap (then stop logging, count drops)
local MAX_ROSTER   = 400   -- profile cap; longest-unseen pruned first

local session              -- current session (last entry in VantageParseDB.sessions)
local openByGuid = {}      -- srcGUID -> its one in-flight row
local myGUID
local myInterruptNames = {}
local zone = ""

-- ---------------------------------------------------------------------------
-- Row lifecycle
-- ---------------------------------------------------------------------------
local function finish(row, out, by, rx)
    if row.out then return end
    row.out = out
    if by then row.by = by end
    if rx then row.rx = rx end
    if out == "done" and row.readyAt then row.miss = true end
    row.readyAt = nil -- transient (GetTime-based); never useful after close
end

local function closeGuid(guid, out, by, rx)
    local row = guid and openByGuid[guid]
    if not row then return end
    finish(row, out, by, rx)
    openByGuid[guid] = nil
end

local function pushRow(row)
    local rows = session.rows
    if #rows >= MAX_ROWS then
        session.counters.dropped = session.counters.dropped + 1
        if session.counters.dropped == 1 then
            Vantage:Print("Parse: session log is full — new casts won't be recorded until next login.")
        end
        return false
    end
    rows[#rows + 1] = row
    return true
end

-- Called by InterruptCue for every evaluated cast; re-evaluations (cooldown
-- changes mid-cast) update the SAME row via overlay.active.__prow.
function M:OnDecision(overlay, unit, spellName, code, readyEntry)
    if not (Vantage.db.parse and session) then return end
    local a = overlay.active
    if not a then return end -- demo casts have no active record; don't log them

    local guid = overlay.guid
    local row = a.__prow
    if not row then
        closeGuid(guid, "?") -- a stale open cast from this mob can't resolve now
        row = {
            t    = time(),
            z    = zone,
            src  = (unit and UnitName(unit)) or "?",
            sp   = spellName,
            sid  = a.spellID,
            pvp  = (unit and UnitIsPlayer(unit)) and true or nil,
            tier = code,
        }
        if not pushRow(row) then return end
        a.__prow = row
        if guid then openByGuid[guid] = row end
    else
        row.tier = code
    end

    if code == "ready" then
        row.win = true
        row.tool = (readyEntry and (readyEntry.label or readyEntry.spell)) or row.tool
        if not row.readyAt then row.readyAt = GetTime() end
    end
end

-- ---------------------------------------------------------------------------
-- The roster: per-player interrupt profiles, fed by every SPELL_INTERRUPT a
-- friendly player lands anywhere near you (grouped or not). A pet's interrupt
-- (a Felhunter's Spell Lock) is credited to the player who owns it, resolved
-- through PartyKicks' pet->owner map.
-- ---------------------------------------------------------------------------
local rosterN = 0

-- combat-log flag masks (numeric fallbacks = the stable classic values)
local TYPE_PLAYER  = COMBATLOG_OBJECT_TYPE_PLAYER or 0x00000400
local REACT_FRIEND = COMBATLOG_OBJECT_REACTION_FRIENDLY or 0x00000010
local AFF_MINE     = COMBATLOG_OBJECT_AFFILIATION_MINE or 0x1
local AFF_PARTY    = COMBATLOG_OBJECT_AFFILIATION_PARTY or 0x2
local AFF_RAID     = COMBATLOG_OBJECT_AFFILIATION_RAID or 0x4

local function isFriendlyPlayer(flags)
    if not (bit and bit.band and flags) then return false end
    if bit.band(flags, TYPE_PLAYER) == 0 then return false end
    return bit.band(flags, REACT_FRIEND) ~= 0
        or bit.band(flags, AFF_MINE + AFF_PARTY + AFF_RAID) ~= 0
end

local function isGrouped(flags)
    return bit and bit.band and flags
        and bit.band(flags, AFF_PARTY + AFF_RAID) ~= 0 or false
end

local function classOf(guid)
    if not (guid and GetPlayerInfoByGUID) then return end
    local ok, _, class = pcall(GetPlayerInfoByGUID, guid)
    if ok then return class end
end

local function rosterTouch(guid, name, flags, tool)
    if not name or name == "" then return end
    local roster = VantageParseDB.roster
    local e = roster[name]
    if not e then
        if rosterN >= MAX_ROSTER then -- prune the longest-unseen profile
            local worstK, worstT
            for k, v in pairs(roster) do
                if not worstT or (v.last or 0) < worstT then worstK, worstT = k, v.last or 0 end
            end
            if worstK then roster[worstK] = nil; rosterN = rosterN - 1 end
        end
        e = { first = time(), kicks = 0, tools = {} }
        roster[name] = e
        rosterN = rosterN + 1
    end
    e.last = time()
    e.kicks = e.kicks + 1
    if tool then e.tools[tool] = (e.tools[tool] or 0) + 1 end
    if isGrouped(flags) then e.gkicks = (e.gkicks or 0) + 1 end
    if not e.class then e.class = classOf(guid) end

    -- per-session tally too, so the web report can show who carried the kicks
    session.kickers[name] = (session.kickers[name] or 0) + 1
end

-- ---------------------------------------------------------------------------
-- Outcomes from the combat log
-- ---------------------------------------------------------------------------
local function onCLEU()
    if not (Vantage.db.parse and session) then return end
    local _, sub, _, srcGUID, _, _, _, dstGUID = CombatLogGetCurrentEventInfo()

    if sub == "SPELL_INTERRUPT" then
        -- A pet's interrupt (a Felhunter's Spell Lock) belongs to its owner: resolve
        -- srcGUID -> the responsible player so the kick counts for the warlock, not
        -- "Felhunter". ownerName is nil for a direct player cast (the source already
        -- IS the player) and for pets we can't map.
        local ownerName, ownerGUID, ownerMine
        if Vantage.PartyKicks then
            ownerName, ownerGUID, ownerMine = Vantage.PartyKicks:OwnerOf(srcGUID)
        end
        local mine = (srcGUID == myGUID) or ownerMine or false

        local row = openByGuid[dstGUID]
        if row then
            local by = mine and "me" or "other"
            local rx
            if by == "me" and row.readyAt then
                rx = math.floor((GetTime() - row.readyAt) * 1000)
            end
            finish(row, "int", by, rx)
            openByGuid[dstGUID] = nil
        end
        if mine then
            session.counters.myInterrupts = session.counters.myInterrupts + 1
        end
        local _, _, _, _, sName, sFlags, _, _, _, _, _, _, kickSpell = CombatLogGetCurrentEventInfo()
        if ownerName then
            -- a pet kick: credit the OWNER (their GUID also resolves the owner's class)
            rosterTouch(ownerGUID, ownerName, sFlags, kickSpell)
            Vantage:Debug("roster: pet interrupt by", sName, "credited to", ownerName)
        elseif isFriendlyPlayer(sFlags) then
            rosterTouch(srcGUID, sName, sFlags, kickSpell)
            Vantage:Debug("roster: interrupt by", sName, "recorded",
                isGrouped(sFlags) and "(grouped)" or "(bystander)")
        else
            -- /vantage debug shows WHY a kick was skipped (pet? hostile? odd flags?)
            Vantage:Debug(("roster: interrupt by %s SKIPPED (flags 0x%x)")
                :format(tostring(sName), sFlags or 0))
        end

    elseif sub == "SPELL_CAST_SUCCESS" then
        local spellName = select(13, CombatLogGetCurrentEventInfo())
        local row = openByGuid[srcGUID]
        if row and row.sp == spellName then
            finish(row, "done")
            openByGuid[srcGUID] = nil
        end
        -- your interrupt CASTS (hit or miss), pet Spell Lock included — keeps
        -- "interrupt casts" consistent with the pet-inclusive "interrupted by you".
        local mine = (srcGUID == myGUID) or (Vantage.PartyKicks and Vantage.PartyKicks:IsMine(srcGUID))
        if mine and myInterruptNames[spellName] then
            session.counters.kickCasts = session.counters.kickCasts + 1
            local tr = openByGuid[dstGUID]
            if tr and tr.tier == "locked" then
                session.counters.wastedKicks = session.counters.wastedKicks + 1
                tr.wk = true
            end
        end

    elseif (sub == "SPELL_AURA_BROKEN" or sub == "SPELL_AURA_BROKEN_SPELL") and srcGUID == myGUID then
        -- a CC YOU broke (DoT/melee/AoE into a sheep, sap, fear) — the anti-stat to
        -- your kicks: stopping a cast is good, shattering the group's CC is not.
        session.counters.ccBreaks = (session.counters.ccBreaks or 0) + 1

    elseif (sub == "SPELL_DISPEL" or sub == "SPELL_STOLEN") and srcGUID == myGUID then
        session.counters.dispels = (session.counters.dispels or 0) + 1

    elseif sub == "SPELL_CAST_FAILED" then
        closeGuid(srcGUID, "stop")

    elseif sub == "UNIT_DIED" then
        closeGuid(dstGUID, "stop")
    end
end

-- ---------------------------------------------------------------------------
-- Session summary (chat): /vantage parse
-- ---------------------------------------------------------------------------
-- p-th percentile of a value list (nearest-rank). Sorts in place.
local function percentile(vals, p)
    local n = #vals
    if n == 0 then return nil end
    table.sort(vals)
    return vals[math.max(1, math.ceil(p / 100 * n))]
end

function M:Summary()
    if not session then
        Vantage:Print("Parse: no session data yet.")
        return
    end
    local rows = session.rows
    local windows, intMe, intOther, thru = 0, 0, 0, 0
    local rxs = {}
    for i = 1, #rows do
        local r = rows[i]
        if r.win then windows = windows + 1 end
        if r.out == "int" then
            if r.by == "me" then intMe = intMe + 1 else intOther = intOther + 1 end
        end
        if r.miss then thru = thru + 1 end
        if r.rx then rxs[#rxs + 1] = r.rx end
    end
    local c = session.counters
    Vantage:Print("Parse — this session:")
    print(("  enemy casts logged: |cffffffff%d|r%s"):format(#rows,
        c.dropped > 0 and (" (|cffff4444%d dropped, log full|r)"):format(c.dropped) or ""))
    print(("  kick windows shown to you: |cffffd100%d|r"):format(windows))
    print(("  interrupted by you: |cff44ff44%d|r   by others: %d"):format(intMe, intOther))
    print(("  |cffff4444let through while your stop was ready: %d|r"):format(thru))
    if #rxs > 0 then
        print(("  reaction (cue -> your interrupt): median |cffffffff%d ms|r · 90th %d ms (n=%d)")
            :format(percentile(rxs, 50), percentile(rxs, 90), #rxs))
    end
    print(("  your interrupt casts: %d   wasted on uninterruptible casts: %d")
        :format(c.kickCasts, c.wastedKicks))
    print(("  CC breaks you caused: |cffe25b4e%d|r   dispels/steals: %d")
        :format(c.ccBreaks or 0, c.dispels or 0))
    -- who carried the kicks this session (any friendly player Vantage saw)
    local ks = {}
    for name, n in pairs(session.kickers or {}) do ks[#ks + 1] = { name, n } end
    if #ks > 0 then
        table.sort(ks, function(a, b) return a[2] > b[2] end)
        local parts = {}
        for i = 1, math.min(4, #ks) do parts[#parts + 1] = ("%s %d"):format(ks[i][1], ks[i][2]) end
        print("  interrupts seen from: " .. table.concat(parts, ", "))
    end
    print("  |cffffd100/vantage export|r — copy this data into the web report")
    print("  |cffffd100/vantage roster|r — lifetime interrupt profiles of everyone seen")
end

-- ---------------------------------------------------------------------------
-- Roster browser (chat): /vantage roster
-- ---------------------------------------------------------------------------
local function classColored(name, class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c and c.colorStr then return ("|c%s%s|r"):format(c.colorStr, name) end
    return name
end

function M:Roster()
    local roster = VantageParseDB and VantageParseDB.roster
    if not roster or not next(roster) then
        Vantage:Print("Roster: no interrupts witnessed yet. Profiles build automatically as Vantage sees friendly players land kicks.")
        return
    end
    local list = {}
    for name, e in pairs(roster) do list[#list + 1] = { name = name, e = e } end
    table.sort(list, function(a, b) return a.e.kicks > b.e.kicks end)
    Vantage:Print(("Roster — %d player%s witnessed interrupting (top %d):")
        :format(#list, #list == 1 and "" or "s", math.min(10, #list)))
    for i = 1, math.min(10, #list) do
        local name, e = list[i].name, list[i].e
        local fav, favN
        for tool, n in pairs(e.tools) do
            if not favN or n > favN then fav, favN = tool, n end
        end
        local when = (date and e.last) and date("%Y-%m-%d", e.last) or "?"
        print(("  %s — |cffffffff%d|r kick%s%s%s · last seen %s"):format(
            classColored(name, e.class), e.kicks, e.kicks == 1 and "" or "s",
            e.gkicks and (" (|cffffd100%d|r in your groups)"):format(e.gkicks) or "",
            fav and (" · " .. fav) or "", when))
    end
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------
function M:OnEnable()
    VantageParseDB = VantageParseDB or {}
    VantageParseDB.sessions = VantageParseDB.sessions or {}
    VantageParseDB.roster = VantageParseDB.roster or {}
    rosterN = 0
    for _ in pairs(VantageParseDB.roster) do rosterN = rosterN + 1 end

    myGUID = UnitGUID("player")
    local list = Vantage.ClassInterrupts and Vantage.ClassInterrupts[Vantage.playerClass]
    if list then
        for i = 1, #list do myInterruptNames[list[i].spell] = true end
    end

    local _, class = UnitClass("player")
    session = {
        meta = {
            player = UnitName("player"),
            realm  = GetRealmName(),
            class  = class,
            addon  = Vantage.version,
            start  = time(),
        },
        counters = { kickCasts = 0, myInterrupts = 0, wastedKicks = 0, dropped = 0, ccBreaks = 0, dispels = 0 },
        rows = {},
        kickers = {}, -- name -> interrupts landed this session (any friendly player)
    }
    table.insert(VantageParseDB.sessions, session)
    while #VantageParseDB.sessions > MAX_SESSIONS do
        table.remove(VantageParseDB.sessions, 1)
    end

    local function updateZone()
        zone = GetRealZoneText() or GetZoneText() or ""
    end
    updateZone()
    Vantage:RegisterEvent("ZONE_CHANGED_NEW_AREA", updateZone)
    Vantage:RegisterEvent("PLAYER_ENTERING_WORLD", updateZone)

    Vantage:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", onCLEU)

    -- casts still open when the world unloads can never resolve
    Vantage:RegisterEvent("PLAYER_LEAVING_WORLD", function()
        for guid in pairs(openByGuid) do closeGuid(guid, "?") end
    end)
end

Vantage.Parse = M
