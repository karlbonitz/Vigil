-- Vantage/Modules/InterruptCue.lua
--
-- THE HERO FEATURE. Given a cast and our intel on it, decide what to show:
--
--   * known + interruptible + your kick is READY   -> gold glow + sound + "INTERRUPT"
--   * known + interruptible + your kick is on CD    -> muted bar (no false urgency)
--   * known + uninterruptible                       -> red bar + padlock (hold your kick)
--   * unknown cast                                  -> neutral bar (no false "KICK!")
--
-- It re-evaluates live casts when your interrupt comes off cooldown, so the glow
-- pops the instant you can actually kick.
local addonName, Vantage = ...
local M = Vantage:NewModule("InterruptCue")

-- the party kick watch's contribution to the cd/aware tiers
local function mateLabel()
    if not (Vantage.db.partyKicks and Vantage.PartyKicks) then return nil end
    return Vantage.PartyKicks:ReadyMateLabel()
end

function M:Evaluate(overlay, unit, spellName, info)
    local cb = overlay.castbar
    local tier            -- human-readable, for /vantage debug
    local code, readyRef  -- machine-readable, for the Vantage Parse logger

    -- Enemy PLAYER casts (PvP): a player's hard cast is interruptible, and our
    -- PvE "do-not-kick" markers must NEVER apply to a player (e.g. an enemy
    -- Paladin's Flash of Light IS kickable, unlike the mob marked uninterruptible).
    -- So for players we ignore the Intel Pack entirely and route straight to
    -- "can I stop this right now?" — no mob database needed, works at any level.
    local pvpTarget = Vantage.db.pvp and unit and UnitIsPlayer(unit)
    if pvpTarget then info = nil end

    -- Uninterruptible: mark it, never glow. (Never for a player target.)
    if (not pvpTarget) and info and info.interruptible == false then
        overlay:HideKick()
        if Vantage.db.showPadlock then overlay.padlock:Show() end
        cb:SetStatusBarColor(Vantage:RGB("locked"))
        tier, code = "UNINTERRUPTIBLE (red + padlock)", "locked"
    else
        overlay.padlock:Hide()

        -- Interruptible: an enemy player's hard cast, a known kickable mob cast,
        -- or unknown-but-user-opted-in.
        local treatAsKickable = pvpTarget
            or (info and info.interruptible == true)
            or (info == nil and Vantage.db.cueUnknown)

        if not treatAsKickable then
            -- unknown cast (and not opted in): neutral, no false alarm
            cb:SetStatusBarColor(Vantage:RGB("unknown"))
            overlay:HideKick()
            tier = (info == nil) and "NOT IN DATABASE -> neutral grey" or "neutral"
            code = "unknown"
        else
            local ready, inRange
            if Vantage.db.interruptCue then
                ready, inRange = Vantage:GetReadyInterrupt(unit)
            end
            if ready and inRange then
                -- you can stop it NOW: full call to action (glow + sound + label;
                -- ShowKick plays the sound only when the cue newly appears)
                cb:SetStatusBarColor(Vantage:RGB("kick"))
                overlay:ShowKick(ready.label)
                tier = "STOP NOW -> " .. (ready.label or "INTERRUPT")
                code, readyRef = "ready", ready
            elseif ready then
                -- ready but you're TOO FAR to land it: gold awareness, no shout.
                -- The range ticker upgrades this to the full cue as you close in.
                cb:SetStatusBarColor(Vantage:RGB("kick"))
                overlay:HideKick()
                tier, code = "kickable, ready but OUT OF RANGE (gold, no popup)", "range"
            elseif Vantage:HasInterrupt(unit) then
                -- you CAN stop it, but the tool is on cooldown: show, don't
                -- shout — and if a groupmate's witnessed interrupt should be
                -- ready, quietly name them instead of leaving the slot empty
                cb:SetStatusBarColor(Vantage:RGB("kickDown"))
                local mt, mr, mg, mb = mateLabel()
                if mt then overlay:ShowMate(mt, mr, mg, mb) else overlay:HideKick() end
                tier = mt and ("kickable, yours down -> mate hint: " .. mt)
                    or "kickable, your interrupt on cooldown (muted)"
                code = "cd"
            else
                -- no interrupt available to you: flag the cast as kickable for
                -- awareness, but no glow/sound/INTERRUPT nag. A ready groupmate
                -- still gets named — this is the healer calling the kick.
                cb:SetStatusBarColor(Vantage:RGB("kick"))
                local mt, mr, mg, mb = mateLabel()
                if mt then overlay:ShowMate(mt, mr, mg, mb) else overlay:HideKick() end
                tier = mt and ("kickable, no tool of yours -> mate hint: " .. mt)
                    or "kickable, no interrupt available -> GOLD awareness (no popup)"
                code = "aware"
            end
        end
    end

    Vantage:Debug("cast:", spellName or "?", "->", tier)

    -- remember the decision on the cast record: CastWatch reads it to pick the
    -- right outcome flash (MISSED needs "a window was up", WASTED needs "locked")
    if overlay.active then overlay.active.code = code end

    -- Vantage Parse: record the decision (and let outcomes attach to it later)
    if Vantage.Parse then
        Vantage.Parse:OnDecision(overlay, unit, spellName, code, readyRef)
    end
end

-- Refresh every in-flight interruptible cast — because your interrupt's
-- cooldown changed, or because you MOVED (range is part of the decision now).
local function reEvaluate()
    for unit, overlay in pairs(Vantage.plates) do
        local active = overlay.active
        if active and overlay.castbar:IsShown() then
            local pvpTarget   = Vantage.db.pvp and UnitIsPlayer(unit)
            local kickable    = active.info and active.info.interruptible == true
            local unknownOptIn = active.info == nil and Vantage.db.cueUnknown
            if pvpTarget or kickable or unknownOptIn then
                M:Evaluate(overlay, unit, active.name, active.info)
            end
        end
    end
end

function M:OnEnable()
    Vantage:RegisterEvent("SPELL_UPDATE_COOLDOWN", reEvaluate)

    -- Movement changes interrupt range without firing any event, so a light
    -- 0.25s pulse keeps the cue honest while casts are up. The loop touches
    -- only plates with an active cast bar — near-zero cost when nothing casts.
    local acc = 0
    local ticker = CreateFrame("Frame")
    ticker:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc < 0.25 then return end
        acc = 0
        if Vantage.db.rangeCheck == false then return end
        reEvaluate()
    end)
end

Vantage.Cue = M
