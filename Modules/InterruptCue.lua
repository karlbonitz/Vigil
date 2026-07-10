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

-- Multi-cast: is THIS the highest-priority kickable cast currently up? With two
-- casters casting kickable spells at once you can only stop one, so only the
-- top-priority cast earns the full shout; the rest stay kickable-colored but quiet,
-- pointing you at the one to kick first. Ties keep both (no false hierarchy).
function M:IsTopKick(overlay, info)
    if Vantage.db.kickPriority == false then return true end
    local myPri = (info and info.priority) or 0
    for _, ov in pairs(Vantage.plates) do
        if ov ~= overlay then
            local a = ov.active
            -- Only a cast you can actually stop RIGHT NOW (code "ready") outranks
            -- this one. A higher-priority cast that's out of range or immune is
            -- already quiet (its own tier hid it), so it must not silence the kick
            -- you CAN land — otherwise both go quiet and you miss the interrupt.
            if a and a.code == "ready" and a.info and a.info.interruptible == true
                and ov.castbar:IsShown() and (a.info.priority or 0) > myPri then
                return false
            end
        end
    end
    return true
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
                cb:SetStatusBarColor(Vantage:RGB("kick"))
                if not M:IsTopKick(overlay, info) then
                    -- kickable, but a HIGHER-priority cast is up elsewhere: kick that
                    -- one first. Keep the kick-colored bar (still interruptible) but
                    -- hold the shout so the full cue points at the right target.
                    overlay:HideKick()
                    tier = "READY, outranked by a higher-priority kick -> quiet"
                else
                    -- you can stop it NOW: full call to action (glow + sound + label;
                    -- ShowKick plays the sound only when the cue newly appears).
                    -- Trust gradient: a community-pack cast you haven't personally
                    -- seen kicked shows the glow but stays QUIET (no alert, tentative
                    -- "?" label) until your first witnessed kick graduates it.
                    local spellID = overlay.active and overlay.active.spellID
                    local tentative = info and info.community == true
                        and not (Vantage.Learn and Vantage.Learn:IsConfirmed(spellID, spellName))
                    -- A cast already inside the reaction window can't be kicked in
                    -- time; show the glow but hold the alert — a beep you can't act
                    -- on is just noise.
                    local rem = cb.endTime and (cb.endTime - (GetTime and GetTime() or 0))
                    local tooLate = rem ~= nil and rem < 0.15
                    if tentative then
                        overlay:ShowKick((ready.label or "INTERRUPT") .. "?", true)
                        tier = "STOP NOW (community, unconfirmed — quiet) -> " .. (ready.label or "INTERRUPT")
                    else
                        overlay:ShowKick(ready.label, tooLate)
                        tier = (tooLate and "STOP NOW (too late for a sound) -> " or "STOP NOW -> ")
                            .. (ready.label or "INTERRUPT")
                    end
                end
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
        -- the ticker drives BOTH the range re-check (movement fires no event) and
        -- the prioritized-cue re-eval (a higher-priority cast starting elsewhere has
        -- to quiet this one). Run while EITHER is on; skip only when both are off.
        if Vantage.db.rangeCheck == false and Vantage.db.kickPriority == false then return end
        reEvaluate()
    end)
end

Vantage.Cue = M
