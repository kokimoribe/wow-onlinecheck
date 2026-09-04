--[[
Control-flow tests for OnlineCheck.  Run:  lua tests/test_illscout.lua

Every case is a way the addon could claim to know something it does not.
Version 0.1 shipped three of them, all reachable without a game running.
]]
package.path = "tests/?.lua;" .. package.path
local mock = require("mock_wow")

-- The mock replaces _G.print so the addon's output can be inspected, which
-- also swallows the harness's own output. Keep the real one.
local say = print

local pass, fail = 0, 0
local function ok(cond, what)
  if cond then pass = pass + 1; say("ok   " .. what)
  else fail = fail + 1; say("FAIL " .. what) end
end

local T
local function load(sendResult)
  for _, t in ipairs({ mock.timers, mock.sent, mock.printed }) do
    for i = #t, 1, -1 do t[i] = nil end
  end
  mock.install(sendResult == nil and 0 or sendResult)
  T = {}
  _G.OnlineCheckTest = T
  assert(loadfile("OnlineCheck/OnlineCheck.lua"))("OnlineCheck")
  return T
end

local function statesOf()
  local out = {}
  for _, n in ipairs(T.order) do out[n] = T.states[n].state end
  return out
end

--------------------------------------------------------------------------
say("-- cancellation --")
--------------------------------------------------------------------------
do
  load(0)
  T.setText("Aaa\nBbb\nCcc")
  T.start()
  mock.drain(3)                       -- all three sends fire
  T.cancel()                          -- cancel *during the settle wait*
  mock.drain()                        -- let the settle timer run
  local s = statesOf()
  ok(s.Aaa == "Unknown" and s.Bbb == "Unknown" and s.Ccc == "Unknown",
     "cancelling during the settle wait leaves names Unknown, not Likely online")
end

do
  load(0)
  T.setText("Aaa\nBbb\nCcc\nDdd")
  T.start()
  mock.tick()                         -- one send
  T.cancel()
  mock.drain()
  local s = statesOf()
  ok(s.Ddd == "Unknown", "cancelling mid-send leaves unsent names Unknown")
  ok(#mock.sent < 4, "cancelling mid-send stops sending")
end

--------------------------------------------------------------------------
say("\n-- send results --")
--------------------------------------------------------------------------
do
  load(mock.RETURNS_NIL)              -- an older API shape returning nothing
  T.setText("Aaa\nBbb")
  T.start()
  mock.drain()
  local s = statesOf()
  ok(s.Aaa == "Unknown" and s.Bbb == "Unknown",
     "a nil send result stays Unknown rather than becoming Likely online")
end

do
  load(3)                             -- AddonMessageThrottle
  T.setText("Aaa")
  T.start()
  mock.drain()
  ok(statesOf().Aaa == "Unknown", "a throttled send stays Unknown")
end

do
  load(0)
  T.setText("Aaa\nBbb")
  T.start()
  mock.drain()
  local s = statesOf()
  ok(s.Aaa == "Likely online" and s.Bbb == "Likely online",
     "a clean run with no replies reaches Likely online")
end

--------------------------------------------------------------------------
say("\n-- replies --")
--------------------------------------------------------------------------
do
  load(0)
  T.setText("Foter\nMántle")
  T.start()
  mock.tick(); mock.tick()            -- both sends
  T.onEvent("No player named 'Foter' is currently playing")   -- no period
  mock.drain()
  local s = statesOf()
  ok(s.Foter == "Unavailable", "an offline reply without a trailing period is matched")
  ok(s["Mántle"] == "Likely online", "a name with no reply is Likely online")
end

do
  load(0)
  T.setText("Foter")
  T.start()
  mock.tick()
  T.onEvent("No player named 'FOTER' is currently playing.")  -- server casing
  mock.drain()
  ok(statesOf().Foter == "Unavailable", "the reply match is case-insensitive")
end

do
  load(0)
  T.setText("Foter")
  T.start()
  mock.tick()
  T.onEvent("Foter has come online.")
  mock.drain()
  ok(statesOf().Foter == "Likely online", "an unrelated system message is ignored")
end

--------------------------------------------------------------------------
say("\n-- the list survives a reload --")
--------------------------------------------------------------------------
do
  load(0)
  _G.OnlineCheckDB = nil
  T.setText("Aaa\nBbb\nCcc")
  ok(_G.OnlineCheckDB and _G.OnlineCheckDB.list == "Aaa\nBbb\nCcc",
     "editing the box saves the list")
end

do
  -- A fresh addon with a saved variable already present, which is what a
  -- reload looks like. Set explicitly so this does not depend on the test
  -- above having passed.
  load(0)
  _G.OnlineCheckDB = { list = "Aaa\nBbb\nCcc" }
  T.login()
  T.start()
  mock.drain()
  ok(#T.order == 3, "the saved list is restored on login")
  _G.OnlineCheckDB = nil
end

--------------------------------------------------------------------------
say("\n-- result order --")
--------------------------------------------------------------------------
do
  -- Within a state group, keep the order they were pasted in: that is the
  -- order the website produced and it carries the ranking you chose. It used
  -- to be alphabetical, and Lua compares strings by byte, so accented names
  -- sorted after every ASCII one and the list looked reversed.
  load(0)
  T.setText("Häzardpay\nFlõw\nMadamarba\nLindaar")
  T.start()
  mock.drain()
  ok(T.order[1] == "Häzardpay" and T.order[4] == "Lindaar",
     "names keep the order they were pasted in")
  ok(T.states["Häzardpay"].idx == 1 and T.states["Lindaar"].idx == 4,
     "each name records its position for sorting inside a state group")
end

--------------------------------------------------------------------------
say("\n-- the paste box is reachable --")
--------------------------------------------------------------------------
do
  -- 0.3 set a width and no height, so the EditBox had no clickable area:
  -- clicks fell through, focus never moved, and Ctrl+V hit the game's
  -- keybinding. A mock cannot click, but it can insist the box is given a
  -- height at all, which is the whole of that bug.
  local src = io.open("OnlineCheck/OnlineCheck.lua"):read("a")
  ok(src:match("paste:SetSize%(%s*%d+%s*,%s*%d+%s*%)") ~= nil,
     "the paste box is given both dimensions, not just a width")
  ok(src:match("paste:SetFocus") ~= nil,
     "something focuses the paste box")
  ok(src:match("pasteBg:EnableMouse%(true%)") ~= nil,
     "clicking the border routes focus to the box")
end

--------------------------------------------------------------------------
say("\n-- prefix registration --")
--------------------------------------------------------------------------
do
  -- `not 0` is false in Lua, so the old boolean test could never fire on a
  -- numeric result. 0 is Success and must stay quiet.
  for _, case in ipairs({
    { value = true,  warns = false, what = "true is accepted quietly" },
    { value = 0,     warns = false, what = "0 (Success) is accepted quietly" },
    { value = false, warns = true,  what = "false warns" },
    { value = 1,     warns = true,  what = "a numeric error code warns" },
    { value = mock.RETURNS_NIL, warns = false, what = "nil is not treated as failure" },
  }) do
    load(0)
    mock.registerResult = case.value
    T.login()
    local warned = false
    for _, line in ipairs(mock.printed) do
      if line:match("prefix registration returned") then warned = true end
    end
    mock.registerResult = nil
    ok(warned == case.warns and mock.registered, case.what)
  end
end

--------------------------------------------------------------------------
say("\n-- parsing --")
--------------------------------------------------------------------------
do
  load(0)
  T.setText("Foter\r\nMántle, Holy Paladin\n  Zuesser  \n\nFoter\nBooga | 133\n")
  T.start()
  mock.drain()
  ok(#T.order == 4, "CRLF, trailing spaces, duplicates and trailing context are handled")
  ok(T.order[2] == "Mántle", "a name is taken from a 'Name, Spec Class' line")
end

say("")
say(string.format("%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
