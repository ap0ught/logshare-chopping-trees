-- LogShare v0.1.0
-- Co-op log ownership split for A Game About Chopping Trees.
--
-- Rules:
--   1. When a player chops a tree, the resulting ground logs are tagged with that player's id.
--   2. On sale (sawmill payout):
--        seller == chopper  -> seller keeps the full price
--        seller ~= chopper  -> seller keeps half, chopper receives the other half
--
-- Requires UE4SS (this package). Client-side; both co-op players should run it
-- so ownership tags and splits stay consistent. Solo play is unaffected
-- (seller always == chopper -> full price).

local MOD_TAG = "[LogShare]"
local UEHelpers = require("UEHelpers")

local DEFAULT_CONFIG = {
    ChopperShare = 0.5,
    VerboseLogging = true,
    WriteGameOwnerProperties = true,
    ShowSplitNotifications = true,
}

local config_ok, loaded_config = pcall(require, "LogShareConfig")
local CONFIG = config_ok and type(loaded_config) == "table" and loaded_config or DEFAULT_CONFIG

local CHOPPER_SHARE = tonumber(CONFIG.ChopperShare) or DEFAULT_CONFIG.ChopperShare
CHOPPER_SHARE = math.max(0.0, math.min(1.0, CHOPPER_SHARE))
local VERBOSE = CONFIG.VerboseLogging ~= false
local WRITE_OWNER_PROPS = CONFIG.WriteGameOwnerProperties ~= false
local SHOW_TOAST = CONFIG.ShowSplitNotifications ~= false

local MOD_VERSION = "0.1.0"

-- ---------------------------------------------------------------------------
-- utilities
-- ---------------------------------------------------------------------------

local function log(fmt, ...)
    local msg = string.format(fmt, ...)
    print(string.format("%s %s\n", MOD_TAG, msg))
end

local function vlog(fmt, ...)
    if VERBOSE then
        log(fmt, ...)
    end
end

local function is_valid(object)
    if not object then
        return false
    end
    local ok, result = pcall(function()
        return object:IsValid()
    end)
    return ok and result
end

local function object_name(object)
    if not is_valid(object) then
        return "<invalid>"
    end
    local ok, result = pcall(function()
        return object:GetFullName()
    end)
    return ok and result or "<name-error>"
end

local function class_name(object)
    if not is_valid(object) then
        return ""
    end
    local ok, result = pcall(function()
        return object:GetClass():GetFName():ToString()
    end)
    return ok and result or ""
end

local function safe_get(object, property)
    if not is_valid(object) then
        return nil
    end
    local ok, value = pcall(function()
        return object:GetPropertyValue(property)
    end)
    if ok then
        return value
    end
    return nil
end

local function safe_set(object, property, value)
    if not is_valid(object) then
        return false
    end
    local ok, err = pcall(function()
        object:SetPropertyValue(property, value)
    end)
    return ok
end

local function address_of(object)
    if not is_valid(object) then
        return nil
    end
    local ok, addr = pcall(function()
        return object:GetAddress()
    end)
    return ok and addr or nil
end

local function find_player()
    local candidates = FindAllOf("BP_Human_C")
    if candidates then
        for _, candidate in ipairs(candidates) do
            if is_valid(candidate) then
                return candidate
            end
        end
    end
    return nil
end

local function all_players()
    local out = {}
    local candidates = FindAllOf("BP_Human_C")
    if candidates then
        for _, candidate in ipairs(candidates) do
            if is_valid(candidate) then
                out[#out + 1] = candidate
            end
        end
    end
    return out
end

local function player_id_of(human)
    if not is_valid(human) then
        return nil, nil
    end
    -- Prefer an explicit id property on the pawn / player state.
    local id = safe_get(human, "PlayerId")
    if id == nil then
        id = safe_get(human, "CachedConnectionPlayerId")
    end
    local ps = safe_get(human, "PlayerState")
    if (id == nil or id == 0) and is_valid(ps) then
        id = safe_get(ps, "PlayerId")
    end
    local name = nil
    if is_valid(ps) then
        name = safe_get(ps, "PlayerName")
    end
    if name == nil or name == "" then
        name = safe_get(human, "PlayerName")
    end
    if name == nil or name == "" then
        local ok, fname = pcall(function()
            return human:GetName()
        end)
        name = ok and fname or "Unknown"
    end
    if id == nil then
        id = tostring(name)
    end
    return id, tostring(name)
end

local function find_player_state_for_id(target_id)
    if target_id == nil then
        return nil
    end
    local candidates = FindAllOf("PlayerState")
    if not candidates then
        candidates = FindAllOf("BP_PlayerState_Base_C")
    end
    if not candidates then
        return nil
    end
    for _, ps in ipairs(candidates) do
        if is_valid(ps) then
            local id = safe_get(ps, "PlayerId")
            if id ~= nil and tostring(id) == tostring(target_id) then
                return ps
            end
        end
    end
    return nil
end

-- Money lives on the player state (GAS / replicated property). Read/write defensively.
local function get_money(ps)
    if not is_valid(ps) then
        return nil
    end
    local v = safe_get(ps, "Money")
    if type(v) == "number" then
        return v
    end
    return nil
end

local function set_money(ps, amount)
    if not is_valid(ps) then
        return false
    end
    amount = math.max(0, math.floor(amount + 0.5))
    if safe_set(ps, "Money", amount) then
        return true
    end
    -- Fallback: try MaxMoney-adjacent naming some builds use.
    return safe_set(ps, "CurrentMoney", amount)
end

local function credit_money(ps, delta)
    if not is_valid(ps) or delta == nil or delta <= 0 then
        return false
    end
    local current = get_money(ps)
    if current == nil then
        return false
    end
    return set_money(ps, current + delta)
end

local function debit_money(ps, delta)
    if not is_valid(ps) or delta == nil or delta <= 0 then
        return false
    end
    local current = get_money(ps)
    if current == nil then
        return false
    end
    return set_money(ps, math.max(0, current - delta))
end

-- ---------------------------------------------------------------------------
-- ownership registry
-- address -> { owner_id, owner_name, tagged_at }
-- ---------------------------------------------------------------------------

local ownership = {}
local last_known_money = nil
local last_local_player = nil
local pending_split_toast = nil
local toast_until = 0.0

local function is_log_actor(actor)
    local name = class_name(actor)
    if name == "" then
        return false
    end
    -- BP_Tree_Log, BP_Tree_Log_Birch, BP_Tree_Log_Pine, BP_Tree_FallenLog, BP_LogPickup
    if string.sub(name, 1, 11) == "BP_Tree_Log" then
        return true
    end
    if name == "BP_Tree_FallenLog_C" then
        return true
    end
    if name == "BP_LogPickup_C" or name == "BP_Pickup_LogPickup_C" then
        return true
    end
    return false
end

local function tag_log(actor, owner_id, owner_name)
    local addr = address_of(actor)
    if not addr then
        return false
    end
    ownership[addr] = {
        owner_id = tostring(owner_id),
        owner_name = tostring(owner_name or owner_id),
        tagged_at = os.clock(),
    }
    if WRITE_OWNER_PROPS then
        -- Game properties found in the shipping exe: LogOwner, LogOwnerId, ChopInstigator, OwnerPlayer.
        local human = find_player()
        if is_valid(human) then
            -- LogOwnerId is typically an id; LogOwner may be an actor/player reference.
            pcall(function()
                actor:SetPropertyValue("LogOwnerId", owner_id)
            end)
            pcall(function()
                actor:SetPropertyValue("ChopInstigator", human)
            end)
        end
    end
    vlog("tagged log %s -> %s (%s)", object_name(actor), tostring(owner_name), tostring(owner_id))
    return true
end

local function ownership_of(actor)
    local addr = address_of(actor)
    if not addr then
        return nil
    end
    return ownership[addr]
end

local function clear_ownership(actor)
    local addr = address_of(actor)
    if addr then
        ownership[addr] = nil
    end
end

-- ---------------------------------------------------------------------------
-- chop tagging: watch new log actors and tag them with the local chopper
-- ---------------------------------------------------------------------------

local function try_tag_new_log(actor)
    if not is_valid(actor) or not is_log_actor(actor) then
        return
    end
    local existing = ownership_of(actor)
    if existing then
        return
    end
    -- Prefer game-provided owner if already set (another client may have tagged it).
    local game_owner = safe_get(actor, "LogOwnerId")
    if game_owner ~= nil and tostring(game_owner) ~= "" and tostring(game_owner) ~= "0" then
        ownership[address_of(actor)] = {
            owner_id = tostring(game_owner),
            owner_name = tostring(game_owner),
            tagged_at = os.clock(),
        }
        vlog("log %s already had LogOwnerId=%s", object_name(actor), tostring(game_owner))
        return
    end
    local human = find_player()
    if not human then
        return
    end
    local id, name = player_id_of(human)
    if id ~= nil then
        tag_log(actor, id, name)
    end
end

-- Also catch existing logs already in the world (late join / reload).
local function scan_existing_logs()
    local actors = FindAllOf("Actor")
    if not actors then
        return 0
    end
    local n = 0
    for _, actor in ipairs(actors) do
        if is_valid(actor) and is_log_actor(actor) then
            local existing = ownership_of(actor)
            if not existing then
                local game_owner = safe_get(actor, "LogOwnerId")
                if game_owner ~= nil and tostring(game_owner) ~= "" and tostring(game_owner) ~= "0" then
                    ownership[address_of(actor)] = {
                        owner_id = tostring(game_owner),
                        owner_name = tostring(game_owner),
                        tagged_at = os.clock(),
                    }
                else
                    local human = find_player()
                    if human then
                        local id, name = player_id_of(human)
                        if id ~= nil then
                            tag_log(actor, id, name)
                            n = n + 1
                        end
                    end
                end
            end
        end
    end
    return n
end

-- ---------------------------------------------------------------------------
-- sale / money watcher
--
-- The sawmill pays out via the Money attribute (GE_AddMoney / OnRep_Money).
-- We watch the local player's money; an increase is treated as a sale of the
-- most recently tagged logs that this player did not chop -> split.
--
-- For a precise per-log split we would hook the sawmill BP. Until those
-- function paths are dumped from a live session, we attribute the increase
-- using the ownership registry: if any unowned-by-local logs were tagged by
-- another player recently, split the increase between local seller and those
-- choppers (evenly among distinct foreign choppers).
-- ---------------------------------------------------------------------------

local function distinct_foreign_choppers(seller_id)
    local by_id = {}
    for _, info in pairs(ownership) do
        if info.owner_id ~= tostring(seller_id) then
            by_id[info.owner_id] = info.owner_name
        end
    end
    local list = {}
    for id, name in pairs(by_id) do
        list[#list + 1] = { id = id, name = name }
    end
    return list
end

local function apply_split(seller_id, seller_name, gain, foreign_choppers)
    -- seller keeps (1 - CHOPPER_SHARE); each foreign chopper gets an equal slice of CHOPPER_SHARE
    local chopper_total = gain * CHOPPER_SHARE
    local seller_keep = gain - chopper_total
    local per = #foreign_choppers > 0 and (chopper_total / #foreign_choppers) or 0

    local seller_ps = find_player_state_for_id(seller_id)
    local local_human = find_player()
    local local_id = local_human and select(1, player_id_of(local_human)) or nil

    -- Seller is usually the local player whose money just went up; debit the
    -- chopper share back so they only keep their half (or full when no split).
    if seller_ps and #foreign_choppers > 0 then
        -- Money already increased by `gain` (full). Take back chopper_total.
        debit_money(seller_ps, chopper_total)
        vlog("seller %s debited %d (kept %d of %d)",
            tostring(seller_name), math.floor(chopper_total + 0.5),
            math.floor(seller_keep + 0.5), math.floor(gain + 0.5))
    end

    for _, ch in ipairs(foreign_choppers) do
        local ch_ps = find_player_state_for_id(ch.id)
        if ch_ps then
            credit_money(ch_ps, per)
            vlog("chopper %s (%s) credited %d", tostring(ch.name), tostring(ch.id), math.floor(per + 0.5))
        else
            -- Other player's PlayerState not found on this client; remember for a toast.
            vlog("chopper %s (%s) not found on this client; split not delivered", tostring(ch.name), tostring(ch.id))
        end
    end

    if SHOW_TOAST then
        local parts = {}
        for _, ch in ipairs(foreign_choppers) do
            parts[#parts + 1] = string.format("%s +%d", ch.name, math.floor(per + 0.5))
        end
        pending_split_toast = string.format(
            "LogShare: sold %d - kept %d | %s",
            math.floor(gain + 0.5),
            math.floor(seller_keep + 0.5),
            table.concat(parts, ", ")
        )
        toast_until = os.clock() + 6.0
    end
end

local function on_money_changed(new_money, old_money)
    local gain = new_money - old_money
    if gain <= 0 then
        -- Money went down (purchase) or unchanged; nothing to split.
        return
    end
    local human = find_player()
    if not human then
        return
    end
    local seller_id, seller_name = player_id_of(human)
    if seller_id == nil then
        return
    end
    local foreign = distinct_foreign_choppers(seller_id)
    if #foreign == 0 then
        -- Solo, or all logs were chopped by the seller: full price already granted.
        vlog("sale +%d by %s (no split needed)", math.floor(gain + 0.5), tostring(seller_name))
        return
    end
    apply_split(seller_id, seller_name, gain, foreign)
end

local function poll_money()
    local human = find_player()
    if not human then
        last_known_money = nil
        return
    end
    local ps = safe_get(human, "PlayerState")
    if not is_valid(ps) then
        return
    end
    local money = get_money(ps)
    if money == nil then
        return
    end
    if last_known_money ~= nil and money ~= last_known_money then
        on_money_changed(money, last_known_money)
    end
    last_known_money = money
end

-- ---------------------------------------------------------------------------
-- on-screen toast
-- ---------------------------------------------------------------------------

local toast_widget = nil

local function ensure_toast_widget()
    if is_valid(toast_widget) then
        return toast_widget
    end
    local controller = UEHelpers.GetPlayerController()
    if not is_valid(controller) then
        return nil
    end
    -- Best-effort: many builds expose a HUD/debug text path. If unavailable,
    -- splits are still logged to the UE4SS console.
    return nil
end

local function maybe_show_toast()
    if not SHOW_TOAST or not pending_split_toast then
        return
    end
    if os.clock() > toast_until then
        pending_split_toast = nil
        return
    end
    -- Log as fallback UI; a widget hook can be added once HUD paths are dumped.
    if VERBOSE then
        log("NOTIFY %s", pending_split_toast)
    end
end

-- ---------------------------------------------------------------------------
-- hooks
-- ---------------------------------------------------------------------------

local function register_chop_hooks()
    -- Delegate signatures found in the shipping exe.
    local hooked = 0
    local candidates = {
        { "/Script/ChoppingTrees.ChoppingTreesGameModeBase:OnTreeChopped" },
        { "/Script/ChoppingTrees.PlayerStateBase:OnTreeChopped" },
    }
    -- Blueprint event paths are game-version specific; NotifyOnNewObject below
    -- is the reliable tagger. Try native delegate hooks opportunistically.
    for _, c in ipairs(candidates) do
        local ok = pcall(function()
            RegisterHook(c[1], function(...)
                local args = { ... }
                -- If the first arg is an actor that looks like a log, tag it.
                for _, a in ipairs(args) do
                    if is_valid(a) and is_log_actor(a) then
                        try_tag_new_log(a)
                    end
                end
            end)
        end)
        if ok then
            hooked = hooked + 1
            vlog("registered hook %s", c[1])
        end
    end
    return hooked
end

local function register_log_spawners()
    local classes = {
        "/Game/Blueprints/_Trees_/Trees/BP_Tree_Log.BP_Tree_Log_C",
        "/Game/Blueprints/_Trees_/Trees/BP_Tree_Log_Birch.BP_Tree_Log_Birch_C",
        "/Game/Blueprints/_Trees_/Trees/BP_Tree_Log_Pine.BP_Tree_Log_Pine_C",
        "/Game/Blueprints/_Trees_/Trees/BP_Tree_Log_Oak.BP_Tree_Log_Oak_C",
        "/Game/Blueprints/_Trees_/Trees/BP_Tree_FallenLog.BP_Tree_FallenLog_C",
        "/Game/Blueprints/_Trees_/Logs/BP_LogPickup.BP_LogPickup_C",
    }
    local registered = 0
    for _, path in ipairs(classes) do
        local ok = pcall(function()
            NotifyOnNewObject(path, function(actor)
                -- Defer one frame so properties settle.
                ExecuteInGameThreadWithDelay(50, function()
                    try_tag_new_log(actor)
                end)
            end)
        end)
        if ok then
            registered = registered + 1
            vlog("watching spawn %s", path)
        end
    end
    -- Fallback: also watch any new Actor whose class name matches (covers
    -- renamed/moved packages without re-dumping paths).
    pcall(function()
        NotifyOnNewObject("Actor", function(actor)
            if is_valid(actor) and is_log_actor(actor) then
                ExecuteInGameThreadWithDelay(50, function()
                    try_tag_new_log(actor)
                end)
            end
        end)
    end)
    return registered
end

-- ---------------------------------------------------------------------------
-- lifecycle
-- ---------------------------------------------------------------------------

local poll_handle = nil
local scan_handle = nil
local toast_handle = nil

local function stop_timers()
    if poll_handle then
        pcall(function() poll_handle:Kill() end)
        poll_handle = nil
    end
    if scan_handle then
        pcall(function() scan_handle:Kill() end)
        scan_handle = nil
    end
    if toast_handle then
        pcall(function() toast_handle:Kill() end)
        toast_handle = nil
    end
end

local function start_timers()
    stop_timers()
    -- Poll money ~4x per second.
    poll_handle = ExecuteInGameThreadWithDelay(250, function tick()
        poll_money()
        maybe_show_toast()
        poll_handle = ExecuteInGameThreadWithDelay(250, tick)
    end)
    -- Re-scan world logs periodically for late tags (other client's logs etc.).
    local scan_count = 0
    scan_handle = ExecuteInGameThreadWithDelay(2000, function rescan()
        scan_count = scan_count + 1
        local n = scan_existing_logs()
        if n > 0 then
            vlog("scan tagged %d new log(s)", n)
        end
        -- Every ~15s also drop ownership of destroyed logs (address reuse guard
        -- is cheap: we just clear entries whose actor is gone).
        if scan_count % 7 == 0 then
            local dead = {}
            for addr, _ in pairs(ownership) do
                -- Can't IsValid an address alone; entries are refreshed on touch.
                -- Prune very old tags (logs despawn when sold).
                -- (Handled by age check below.)
            end
            local now = os.clock()
            for addr, info in pairs(ownership) do
                if now - (info.tagged_at or 0) > 600 then
                    dead[addr] = true
                end
            end
            for addr in pairs(dead) do
                ownership[addr] = nil
            end
        end
        scan_handle = ExecuteInGameThreadWithDelay(2000, rescan)
    end)
    toast_handle = ExecuteInGameThreadWithDelay(500, function toast_tick()
        maybe_show_toast()
        toast_handle = ExecuteInGameThreadWithDelay(500, toast_tick)
    end)
end

local function bootstrap()
    log("v%s loading (chopper share %.0f%%)", MOD_VERSION, CHOPPER_SHARE * 100)
    local hooks = register_chop_hooks()
    local watchers = register_log_spawners()
    local tagged = scan_existing_logs()
    log("ready: %d spawn watcher(s), %d native hook(s), %d existing log(s) tagged",
        watchers, hooks, tagged)
    start_timers()
end

-- Wait until the world exists before scanning.
ExecuteInGameThreadWithDelay(1500, function()
    local ok, err = pcall(bootstrap)
    if not ok then
        log("bootstrap failed: %s", tostring(err))
    end
end)

log("loaded; deferring bootstrap 1.5s")
