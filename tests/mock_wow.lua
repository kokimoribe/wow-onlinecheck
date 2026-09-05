--[[
Enough of the WoW API to load OnlineCheck.lua and drive its control flow.

Written because the client is the one place I cannot test, and every defect
found in 0.1 -- cancel not stopping the settle timer, an unexpected send
result becoming "Likely online", a boolean test on a numeric return -- was a
control-flow bug reachable without a game running.

Timers are a queue you fire by hand, so a test can cancel *between* the last
send and the settle callback, which is precisely where the cancel bug lived.
]]
local M = { timers = {}, sent = {}, printed = {} }

-- Pass M.RETURNS_NIL to make SendAddonMessage return nil, which a plain
-- `nil` argument cannot express through a default.
M.RETURNS_NIL = setmetatable({}, { __tostring = function() return "<nil>" end })

function M.install(sendResult)
  if sendResult == M.RETURNS_NIL then sendResult = nil end
  M.registered = false
  M.widgets = {}
  _G.UIParent = {}
  _G.UISpecialFrames = {}
  _G.SELECTED_DOCK_FRAME = {}
  _G.ChatFontNormal = {}
  _G.BackdropTemplateMixin = nil
  _G.ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
  _G.Enum = { SendAddonMessageResult = { Success = 0, TargetOffline = 12 } }

  -- Unknown methods return 0, not the frame: the addon does arithmetic on
  -- getter results (GetFrameLevel() - 1), and a table there just errors.
  local function stub()
    local t = {}
    M.widgets[#M.widgets + 1] = t
    setmetatable(t, { __index = function() return function() return 0 end end })
    t.CreateFontString = function() return stub() end
    t.CreateTexture = function() return stub() end
    -- The real SetText fires OnTextChanged; a mock that does not makes any
    -- save-on-edit behaviour invisible to a test.
    t.SetText = function(self, v)
      self.__text = v
      local h = self._OnTextChanged
      if h then h(self, false) end
      return self
    end
    t.GetText = function(self) return self.__text or "" end
    t.SetScript = function(self, ev, fn) self["_" .. ev] = fn; return self end
    t.GetScript = function(self, ev) return self["_" .. ev] end
    -- Show/Hide track a flag rather than doing nothing, so a test can tell
    -- whether a panel actually opened. The stub used to answer false always,
    -- which would have made any assertion about visibility pass without
    -- meaning anything.
    t.Show = function(self) self.__shown = true; return self end
    t.Hide = function(self) self.__shown = false; return self end
    t.IsShown = function(self) return self.__shown == true end
    return t
  end
  _G.CreateFrame = function() return stub() end
  _G.tinsert = table.insert
  _G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
  _G.date = os.date
  _G.time = os.time
  _G.GetTime = os.clock
  _G.FauxScrollFrame_Update = function() end
  _G.FauxScrollFrame_GetOffset = function() return 0 end
  _G.FauxScrollFrame_OnVerticalScroll = function() end
  _G.ChatFrame_OpenChat = function(t) M.opened = t end
  _G.SlashCmdList = {}
  _G.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    M.printed[#M.printed + 1] = table.concat(parts, " ")
  end
  _G.C_Timer = { After = function(delay, fn)
    M.timers[#M.timers + 1] = { delay = delay, fn = fn }
  end }
  _G.C_ChatInfo = {
    RegisterAddonMessagePrefix = function()
      M.registered = true
      if M.registerResult == M.RETURNS_NIL then return nil end
      if M.registerResult ~= nil then return M.registerResult end
      return true
    end,
    SendAddonMessage = function(_, _, _, target)
      M.sent[#M.sent + 1] = target
      return sendResult
    end,
  }
end

--- Fire the next queued timer. Returns false when the queue is empty.
function M.tick()
  local t = table.remove(M.timers, 1)
  if not t then return false end
  t.fn()
  return true
end

function M.drain(limit)
  local n = 0
  while M.tick() do
    n = n + 1
    if limit and n >= limit then break end
  end
  return n
end

return M
