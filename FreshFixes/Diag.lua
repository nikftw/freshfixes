local ADDON, FF = ...

-- Error recorder. Keeps every Lua error, Lua warning and blocked action of
-- the session in FreshFixesErrors (saved on /reload or logout), so problems
-- can be read back from WTF\...\SavedVariables\FreshFixes.lua without
-- copying anything out of the game. Errors still reach the game's own error
-- window as usual. /ff errors shows a summary; /ff errors clear empties it.
local MAX = 200

local issecret = issecretvalue
local function safe(v)
    if issecret and issecret(v) then
        return "<secret>"
    end
    local ok, s = pcall(tostring, v)
    return ok and s or "<?>"
end

local pending = {} -- before SavedVariables load
local log -- FreshFixesErrors.list once loaded
local seen = {} -- [kind .. message] = entry

local function record(kind, msg, stack)
    msg = safe(msg)
    local key = kind .. "\0" .. msg
    local e = seen[key]
    if e then
        e.count = e.count + 1
        e.last = time()
        return
    end
    e = { kind = kind, msg = msg, stack = stack and safe(stack) or nil, count = 1, first = time(), last = time() }
    seen[key] = e
    local list = log or pending
    if #list < MAX then
        list[#list + 1] = e
    end
end
FF.RecordError = record

local prev = geterrorhandler()
seterrorhandler(function(msg, ...)
    pcall(record, "error", msg, debugstack and debugstack(3) or nil)
    if prev then
        return prev(msg, ...)
    end
end)

local f = CreateFrame("Frame")
for _, ev in ipairs({ "ADDON_LOADED", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "MACRO_ACTION_BLOCKED", "LUA_WARNING" }) do
    pcall(f.RegisterEvent, f, ev)
end
f:SetScript("OnEvent", function(_, event, a, b)
    if event == "ADDON_LOADED" then
        if a == ADDON then
            local version, build = GetBuildInfo()
            if type(FreshFixesErrors) ~= "table" or FreshFixesErrors.build ~= build then
                FreshFixesErrors = { list = {} } -- new client build: start over
            end
            FreshFixesErrors.build = build
            FreshFixesErrors.version = version
            FreshFixesErrors.addon = C_AddOns.GetAddOnMetadata(ADDON, "Version")
            FreshFixesErrors.list = FreshFixesErrors.list or {}
            log = FreshFixesErrors.list
            for _, e in ipairs(log) do
                seen[e.kind .. "\0" .. e.msg] = e
            end
            for _, e in ipairs(pending) do
                if #log < MAX then
                    log[#log + 1] = e
                end
            end
            pending = nil
        end
        return
    end
    if event == "LUA_WARNING" then
        pcall(record, "warning", b or a)
    else
        -- a = addon blamed, b = protected function it tried to call
        pcall(record, event, safe(a) .. " -> " .. safe(b), debugstack and debugstack(2) or nil)
    end
end)

FF.Command("errors", function(rest)
    local list = log or pending or {}
    if rest == "clear" then
        wipe(list)
        wipe(seen)
        FF.print("Error log cleared")
        return
    end
    FF.print(("%d distinct problem%s recorded this build (saved on /reload or logout)"):format(#list, #list == 1 and "" or "s"))
    for i = math.max(1, #list - 9), #list do
        local e = list[i]
        print(("  %d. [%s x%d] %s"):format(i, e.kind, e.count, e.msg:sub(1, 160)))
    end
end, "recorded Lua errors (errors clear to empty)")
