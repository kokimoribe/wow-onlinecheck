--[[
OnlineCheck -- paste a list of character names and check who is online.

How it works, and what it can and cannot tell you:

  We send a silent addon message to each name. Nothing is delivered to them:
  an addon message on an unregistered prefix is invisible to a player whose
  client has no handler for it. If the character is not reachable, the server
  answers with ERR_CHAT_PLAYER_NOT_FOUND_S, naming them. Measured latency on
  a TBC Anniversary realm was ~200ms.

  So a returned error is a positive observation. Silence is not: it means no
  error arrived within our waiting window, which is evidence and not proof.
  That asymmetry is why the three states are worded the way they are, and why
  nothing here ever says "Offline" or "Online" on its own authority:

    Unavailable    the server named them as not currently playing
    Likely online  the send was accepted and no error came back in time
    Unknown        the send failed, was throttled, or the run was cancelled

  A cancelled or broken run must never turn the list green, so every name
  starts Unknown and only moves on an observation.

  It also cannot distinguish "offline" from "renamed, transferred or deleted"
  -- the server's message is the same for both.

This sends nothing to anyone and never whispers automatically. Clicking a
result opens the chat box with /w prefilled; you type and send it yourself.
]]

local ADDON_NAME = ...
local PREFIX = "ONLINECHECK"

-- Documented allowance is 10 messages per prefix, regenerating 1/second.
-- Pacing at one per second stays inside that without needing to model the
-- burst, and a 50-name list finishes in about a minute.
local SEND_INTERVAL = 1.0
-- How long to keep listening after the last send before calling the
-- remainder "Likely online". Starting value, not a proven maximum: one 200ms
-- observation says nothing about the tail.
local SETTLE_SECONDS = 5.0

local UNKNOWN, UNAVAILABLE, LIKELY = "Unknown", "Unavailable", "Likely online"

local COLOR = {
  [LIKELY]      = "|cff54be87",
  [UNAVAILABLE] = "|cff8b92a2",
  [UNKNOWN]     = "|cffe0a33c",
}

--------------------------------------------------------------------------
-- state
--------------------------------------------------------------------------
local names, byName, order = {}, {}, {}
local running, cancelled, sentCount = false, false, 0
local warnedResult = false
local lastRunAt

-- Resolve Success from the client rather than assuming 0, but fall back to 0
-- if the enum is missing.
local SUCCESS = (Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success) or 0

--------------------------------------------------------------------------
-- Build a Lua pattern from the localised "no player named %s" string, so
-- this works on a non-English client instead of matching hardcoded English.
--------------------------------------------------------------------------
-- Deliberately not anchored at the end. The message observed in TBC Anniversary
-- printed without a trailing period, and if the pattern misses, every name
-- silently becomes "Likely online" -- a broken checker turning the list green
-- is the worst failure this can have, so the match is loose and a run that
-- finds nothing warns instead.
local function toPattern(fmt)
  local p = fmt:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
  p = p:gsub("%%%%s", "(.-)")
  p = p:gsub("%%%.$", "")                  -- tolerate a missing final period
  return "^" .. p
end
local NOT_FOUND_PATTERN = toPattern(ERR_CHAT_PLAYER_NOT_FOUND_S or "No player named '%s' is currently playing.")

--------------------------------------------------------------------------
-- ui
--------------------------------------------------------------------------
local f = CreateFrame("Frame", "OnlineCheckFrame", UIParent, "BasicFrameTemplateWithInset")
f:SetSize(360, 522)
f:SetPoint("CENTER")
f:SetMovable(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", f.StopMovingOrSizing)
f:Hide()
f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
f.title:SetPoint("TOP", 0, -5)
f.title:SetText("OnlineCheck")
tinsert(UISpecialFrames, "OnlineCheckFrame")   -- Escape closes it

local help = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
help:SetPoint("TOPLEFT", 14, -30)
help:SetPoint("TOPRIGHT", -14, -30)
help:SetJustifyH("LEFT")
help:SetText("Click the box and paste names, one per line. Escape leaves it.")

-- paste box
local pasteScroll = CreateFrame("ScrollFrame", "OnlineCheckPasteScroll", f, "UIPanelScrollFrameTemplate")
pasteScroll:SetPoint("TOPLEFT", 14, -50)
pasteScroll:SetSize(310, 126)
local paste = CreateFrame("EditBox", nil, pasteScroll)
paste:SetMultiLine(true)
paste:SetFontObject(ChatFontNormal)
-- A height, not just a width. Without one the EditBox has no clickable area
-- at all: clicks fall through to the world, focus never moves, and Ctrl+V
-- reaches the game's keybinding instead of the box. Taller than the visible
-- scroll frame so there is room to scroll a long list.
paste:SetSize(300, 400)
paste:SetMaxLetters(0)
paste:EnableMouse(true)
paste:SetAutoFocus(false)
paste:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
pasteScroll:SetScrollChild(paste)
local pasteBg = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate")
pasteBg:SetPoint("TOPLEFT", pasteScroll, -6, 6)
pasteBg:SetPoint("BOTTOMRIGHT", pasteScroll, 26, -6)
if pasteBg.SetBackdrop then
  pasteBg:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
                        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                        tile = true, tileSize = 16, edgeSize = 12,
                        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  pasteBg:SetBackdropColor(0, 0, 0, 0.5)
end
pasteBg:SetFrameLevel(pasteScroll:GetFrameLevel() - 1)
-- The visible border is a separate frame from the EditBox, so a click on the
-- padding around the text would otherwise do nothing. Route it to the box.
pasteBg:EnableMouse(true)
pasteBg:SetScript("OnMouseDown", function() paste:SetFocus() end)

-- Opening the window is nearly always a prelude to pasting, so take focus.
-- Escape clears it (and a second Escape closes the window).
f:SetScript("OnShow", function() paste:SetFocus() end)



local pasteCount = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
pasteCount:SetPoint("TOPRIGHT", pasteScroll, "BOTTOMRIGHT", 20, -4)
pasteCount:SetJustifyH("RIGHT")

-- Count the names as they are typed or pasted, and remember the list across
-- reloads: re-pasting the same twenty names after every /reload is exactly
-- the kind of small friction that stops a tool being used.
local function countNames(text)
  local n = 0
  local seen = {}
  for line in (text or ""):gmatch("[^\r\n]+") do
    local name = line:match("^%s*(.-)%s*$"):match("^([^%s,;|]+)")
    if name and name ~= "" and not seen[name] then seen[name] = true; n = n + 1 end
  end
  return n
end

local function onPasteChanged()
  local n = countNames(paste:GetText())
  pasteCount:SetText(n == 0 and "" or (n == 1 and "1 name" or n .. " names"))
  OnlineCheckDB = OnlineCheckDB or {}
  OnlineCheckDB.list = paste:GetText()
end
paste:SetScript("OnTextChanged", onPasteChanged)

local checkBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
checkBtn:SetSize(90, 22)
checkBtn:SetPoint("TOPLEFT", 14, -196)
checkBtn:SetText("Check")

local cancelBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
cancelBtn:SetSize(90, 22)
cancelBtn:SetPoint("LEFT", checkBtn, "RIGHT", 6, 0)
cancelBtn:SetText("Cancel")
cancelBtn:Disable()

-- Its own full-width line. Squeezed between Cancel and the window edge it
-- wrapped onto two lines and overlapped the results.
local status = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
status:SetPoint("TOPLEFT", 16, -226)
status:SetPoint("TOPRIGHT", -16, -226)
status:SetJustifyH("LEFT")
status:SetWordWrap(false)
status:SetText("")

-- results
local listScroll = CreateFrame("ScrollFrame", "OnlineCheckListScroll", f, "FauxScrollFrameTemplate")
listScroll:SetPoint("TOPLEFT", 14, -248)
listScroll:SetSize(310, 234)

-- Clicking a row to open a whisper is the reason the results are buttons,
-- and nothing about a list of names suggests it. Reported as a nice
-- surprise by the first person to use this, which is another way of saying
-- it was undiscoverable.
local rowHint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
rowHint:SetPoint("TOPLEFT", 16, -488)
rowHint:SetText("Click a result to whisper that character.")

local ROWS, ROW_H = 13, 18
local rows = {}
for i = 1, ROWS do
  local b = CreateFrame("Button", nil, f)
  b:SetSize(306, ROW_H)
  b:SetPoint("TOPLEFT", listScroll, "TOPLEFT", 0, -(i - 1) * ROW_H)
  b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  -- Two positioned FontStrings, not one string padded with %-13s. The game
  -- font is proportional, so space-padding lines nothing up: "Flõw" and
  -- "Luvtummyrubs" pad to the same character count and different widths.
  b.name = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  b.name:SetPoint("LEFT", 6, 0)
  b.name:SetWidth(150)
  b.name:SetJustifyH("LEFT")
  b.state = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  b.state:SetPoint("LEFT", 162, 0)
  b.state:SetJustifyH("LEFT")
  b:SetScript("OnClick", function(self)
    if not self.who then return end
    -- Opens the chat box with /w prefilled. Nothing is sent for you.
    ChatFrame_OpenChat("/w " .. self.who .. " ", SELECTED_DOCK_FRAME)
  end)
  b:Hide()
  rows[i] = b
end

--------------------------------------------------------------------------
-- rendering
--------------------------------------------------------------------------
local RANK = { [LIKELY] = 1, [UNKNOWN] = 2, [UNAVAILABLE] = 3 }

local function sortedNames()
  local out = {}
  for _, n in ipairs(order) do out[#out + 1] = n end
  table.sort(out, function(a, b)
    local ra, rb = RANK[byName[a].state], RANK[byName[b].state]
    if ra ~= rb then return ra < rb end
    -- Then the order you pasted them in, so whatever ordering the list
    -- arrived with survives the trip through the clipboard.
    -- This used to be alphabetical, and since Lua compares strings by byte,
    -- every accented name sorted after every ASCII one -- so a list starting
    -- "Häzardpay, Flõw, Madamarba" came back with Madamarba first and the
    -- two accented names at the end, which reads as reversed.
    return byName[a].idx < byName[b].idx
  end)
  return out
end

local function counts()
  local c = { [LIKELY] = 0, [UNAVAILABLE] = 0, [UNKNOWN] = 0 }
  for _, n in ipairs(order) do c[byName[n].state] = c[byName[n].state] + 1 end
  return c
end

local function refresh()
  local sorted = sortedNames()
  FauxScrollFrame_Update(listScroll, #sorted, ROWS, ROW_H)
  local offset = FauxScrollFrame_GetOffset(listScroll)
  for i = 1, ROWS do
    local idx = i + offset
    local row = rows[i]
    local name = sorted[idx]
    if name then
      local e = byName[name]
      row.who = name
      row.name:SetText(name)
      row.state:SetText(COLOR[e.state] .. e.state .. "|r")
      row:Show()
    else
      row.who = nil
      row:Hide()
    end
  end
  local c = counts()
  local when = (not running and lastRunAt) and ("  |cff5f6678checked " .. date("%H:%M", lastRunAt) .. "|r") or ""
  status:SetText(string.format("|cff54be87%d likely|r  |cff8b92a2%d unavailable|r  |cffe0a33c%d unknown|r%s",
    c[LIKELY], c[UNAVAILABLE], c[UNKNOWN], when))
end
listScroll:SetScript("OnVerticalScroll", function(self, offset)
  FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, refresh)
end)

--------------------------------------------------------------------------
-- the check
--------------------------------------------------------------------------
local function setState(name, state)
  local e = byName[name]
  if not e then return end
  -- An explicit observation always wins over an assumption.
  if state == UNAVAILABLE or e.state ~= UNAVAILABLE then
    e.state, e.at = state, time()
  end
end

-- A per-row timestamp was noise. Every Check wipes the list and starts over,
-- so every row in a run shares the same minute -- the column answered a
-- question nobody could ask. The run's time belongs in the status line once.
local function finish(msg)
  lastRunAt = time()
  running, cancelled = false, false
  checkBtn:Enable()
  cancelBtn:Disable()
  refresh()
  print("|cff8b7bf0OnlineCheck|r " .. msg)
end

local ticker
local debugging = false

local function settle()
  -- Cancelling during the wait must also stop this. Without the check the
  -- timer still fired and promoted everything to "Likely online" after the
  -- run had been abandoned -- the cancel button appeared to work and did not.
  if cancelled then
    finish("cancelled. Names not yet answered stay Unknown.")
    return
  end
  -- Everything still Unknown after the settle window had its send accepted
  -- and produced no error, so it is *likely* reachable. Deliberately not
  -- called Online: no positive observation was made.
  for _, n in ipairs(order) do
    local e = byName[n]
    if e.state == UNKNOWN and e.sent then setState(n, LIKELY) end
  end
  local c = counts()
  -- Nothing came back unavailable. That might be true, or the reply pattern
  -- might not match this client's wording -- and this warning does not tell
  -- the two apart, so it asks rather than concludes. It certainly does not
  -- validate the green results.
  if sentCount > 0 and c[UNAVAILABLE] == 0 then
    print("|cffe0a33cOnlineCheck|r nothing came back unavailable. Worth checking a "
      .. "character you know is offline before trusting this run -- if that one also "
      .. "reads Likely online, run |cffffffff/onlinecheck debug|r and send the raw lines.")
  end
  finish(string.format("done -- %d checked.", sentCount))
end

local function step(i)
  if cancelled then
    finish("cancelled. Names not yet checked stay Unknown.")
    return
  end
  local name = order[i]
  if not name then
    status:SetText(string.format("waiting %ds for late replies...", SETTLE_SECONDS))
    C_Timer.After(SETTLE_SECONDS, settle)
    return
  end
  local ok = C_ChatInfo.SendAddonMessage(PREFIX, "1", "WHISPER", name)
  -- Only an explicit Success counts. This previously also accepted nil and
  -- true "defensively", which meant an unexpected API result became a
  -- successful send and then, five seconds later, "Likely online" -- a
  -- fabricated observation. Anything we do not recognise leaves the name
  -- Unknown and says so once, loudly, rather than guessing.
  if ok == SUCCESS then
    byName[name].sent = true
    sentCount = sentCount + 1
  else
    setState(name, UNKNOWN)
    byName[name].sent = false
    if not warnedResult then
      warnedResult = true
      print(("|cffe0a33cOnlineCheck|r send returned %s, which is not Success (%s). "
        .. "Those names stay Unknown. Please report this value."):format(tostring(ok), tostring(SUCCESS)))
    end
  end
  status:SetText(string.format("checking %d of %d...", i, #order))
  refresh()
  C_Timer.After(SEND_INTERVAL, function() step(i + 1) end)
end

local function startCheck()
  local text = paste:GetText() or ""
  wipe(names); wipe(byName); wipe(order)
  for line in text:gmatch("[^\r\n]+") do
    local n = line:match("^%s*(.-)%s*$")
    n = n:match("^([^%s,;|]+)")            -- tolerate "Name, Spec Class" pastes
    if n and n ~= "" and not byName[n] then
      order[#order + 1] = n
      byName[n] = { state = UNKNOWN, sent = false, idx = #order }
    end
  end
  if #order == 0 then
    print("|cff8b7bf0OnlineCheck|r nothing to check -- paste names first, one per line.")
    return
  end
  running, cancelled, sentCount = true, false, 0
  checkBtn:Disable()
  cancelBtn:Enable()
  refresh()
  print(string.format("|cff8b7bf0OnlineCheck|r checking %d names, about %ds.",
    #order, math.ceil(#order * SEND_INTERVAL + SETTLE_SECONDS)))
  step(1)
end

checkBtn:SetScript("OnClick", startCheck)
cancelBtn:SetScript("OnClick", function() cancelled = true end)

--------------------------------------------------------------------------
-- events
--------------------------------------------------------------------------
f:RegisterEvent("CHAT_MSG_SYSTEM")
f:SetScript("OnEvent", function(_, event, msg)
  if event ~= "CHAT_MSG_SYSTEM" or not running then return end
  local who = msg:match(NOT_FOUND_PATTERN)
  if not who then
    if debugging then print("|cff5f6678OnlineCheck raw:|r " .. msg) end
    return
  end
  -- Match case-insensitively: the server echoes its own capitalisation.
  for _, n in ipairs(order) do
    if n:lower() == who:lower() then
      setState(n, UNAVAILABLE)
      refresh()
      return
    end
  end
end)

--------------------------------------------------------------------------
-- demo
--------------------------------------------------------------------------

-- Fills the window with fixed results so the interface can be photographed
-- without publishing a real player's name next to their online status --
-- and so the same picture can be retaken after a layout change instead of
-- depending on who is logged in.
--
-- Warcraft NPCs rather than names invented to look like players. An
-- invented name is only unused if you check, and there are millions of
-- characters: "Emberlyn" reads as plausible precisely because somebody
-- would pick it, which is the whole problem. Nobody mistakes Thrall for a
-- recruit, so the screenshot is unambiguously a demo. TBC-era figures
-- alongside the familiar ones, since that is the client this runs on.
--
-- No apostrophes: player names cannot contain them, so "Kael'thas" would be
-- a shape this box never really receives. Fourteen names, so the thirteen-row
-- list is full and visibly scrollable, in a mix that shows all three states.
--
-- Sends nothing and contacts nobody.
local DEMO = {
  { "Thrall", LIKELY }, { "Sylvanas", UNAVAILABLE }, { "Jaina", LIKELY },
  { "Illidan", UNAVAILABLE }, { "Khadgar", UNAVAILABLE }, { "Maiev", LIKELY },
  { "Akama", UNKNOWN }, { "Velen", UNAVAILABLE }, { "Vashj", UNAVAILABLE },
  { "Kaelthas", LIKELY }, { "Gruul", UNAVAILABLE }, { "Magtheridon", UNKNOWN },
  { "Kazzak", UNAVAILABLE }, { "Nazgrel", UNAVAILABLE },
}

local function demo()
  wipe(names); wipe(byName); wipe(order)
  local lines = {}
  for i, e in ipairs(DEMO) do
    order[i], lines[i] = e[1], e[1]
    byName[e[1]] = { state = e[2], sent = true, idx = i }
  end
  paste:SetText(table.concat(lines, "\n"))
  running, cancelled = false, false
  lastRunAt = time()
  f:Show()
  refresh()
  print("|cff8b7bf0OnlineCheck|r showing demo data -- Warcraft NPCs, not players. "
    .. "Nothing was sent and nobody was contacted. Run a real check to replace them.")
end

SLASH_ONLINECHECK1 = "/onlinecheck"
SlashCmdList.ONLINECHECK = function(arg)
  if arg and arg:lower():match("debug") then
    debugging = not debugging
    print("|cff8b7bf0OnlineCheck|r debug " .. (debugging and "on -- raw system messages will print during a check."
      or "off."))
    return
  end
  if arg and arg:lower():match("demo") then
    demo()
    return
  end
  if arg and arg:lower():match("pattern") then
    print("|cff8b7bf0OnlineCheck|r matching: " .. NOT_FOUND_PATTERN)
    return
  end
  if f:IsShown() then f:Hide() else f:Show() end
end

local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
init:SetScript("OnEvent", function()
  -- `not 0` is false in Lua, so testing this as a boolean silently passed
  -- every numeric result including the error codes. Judge the value.
  OnlineCheckDB = OnlineCheckDB or {}
  if OnlineCheckDB.list and OnlineCheckDB.list ~= "" then
    paste:SetText(OnlineCheckDB.list)
  end
  local reg = C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
  if reg == false or (type(reg) == "number" and reg ~= 0) then
    print(("|cffe0a33cOnlineCheck|r prefix registration returned %s; checks will probably "
      .. "fail."):format(tostring(reg)))
  end
  print("|cff8b7bf0OnlineCheck|r loaded. /onlinecheck to open.")
end)

-- Test seam. `OnlineCheckTest` is never defined in the client; the harness in
-- addon/tests defines it before loading this file. The state machine lives in
-- locals and is precisely the part that must not lie about what it observed,
-- and version 0.1 shipped three ways for it to do exactly that.
if OnlineCheckTest then
  OnlineCheckTest.start   = startCheck
  OnlineCheckTest.cancel  = function() cancelled = true end
  OnlineCheckTest.setText = function(t) paste:SetText(t) end
  OnlineCheckTest.getText = function() return paste:GetText() end
  OnlineCheckTest.states  = byName
  OnlineCheckTest.order   = order
  OnlineCheckTest.onEvent = function(msg) f:GetScript("OnEvent")(f, "CHAT_MSG_SYSTEM", msg) end
  OnlineCheckTest.login   = function() init:GetScript("OnEvent")(init, "PLAYER_LOGIN") end
end
