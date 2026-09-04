# OnlineCheck

Paste a list of character names and check who's online.

Useful when you have more names than you want to check one at a time, and you
would rather not add them all to your friends list to find out.

## Install

Download `OnlineCheck.zip` from the
[latest release](https://github.com/kokimoribe/wow-onlinecheck/releases/latest)
and unzip it so that `OnlineCheck\OnlineCheck.toc` sits directly inside your
`Interface\AddOns` folder.

If you're not sure where that is, find it from the Battle.net launcher: select
the game, then the gear icon next to Play → **Show in Explorer**. Each game
version has its own install directory.

Restart the client for a first install. `/reload` is enough afterwards.

## Use

    /onlinecheck            open and close the window
    /onlinecheck debug      print raw system messages during a check
    /onlinecheck pattern    show the pattern replies are matched against

Paste names into the box, one per line, and click **Check**. It paces one
check per second, so fifty names take about a minute, and **Cancel** stops it
at any point. Your list is remembered between reloads.

Lines can carry trailing text — `Thrall, Enhancement Shaman` and `Thrall | 133`
both work — so a list copied out of a spreadsheet usually pastes as-is.

Clicking a result opens the chat box with `/w Name ` already typed. **It never
sends anything for you.**

## Results

| | |
|---|---|
| **Likely online** | The check was accepted and the server didn't report this character as offline. |
| **Unavailable** | The server reported this character as not currently playing. |
| **Unknown** | The check failed, was throttled, or the run was cancelled. Nothing was learned. |

Results are grouped **Likely online → Unknown → Unavailable**, and within each
group they keep the order you pasted them in.

Every name starts **Unknown** and only moves when something is observed, so a
cancelled or interrupted run leaves the list honest rather than optimistic.

## How it works, and what it can't tell you

Each check sends a hidden addon message to the character's client. No whisper
is sent, and a client with no handler for that message discards it, so there
is nothing for the player to see. If the character isn't reachable, the server
replies with its standard "no player named" error, which names them.

So **Unavailable** is a positive observation — the server said so.
**Likely online** is not. It means no offline error arrived before the check
finished, which is good evidence and not a confirmation. Two things can make
it wrong: an offline reply arriving late, and someone logging out immediately
after the check.

It also can't tell **offline** apart from **renamed, transferred or deleted** —
the server sends the same message for all of them.

And it doesn't run `/who` or show level, class, guild or zone. It answers one
question: can you whisper this person right now.

## Compatibility

Developed and used on **TBC Anniversary (2.5.6)**, English client.

The reply pattern is built from the client's own `ERR_CHAT_PLAYER_NOT_FOUND_S`
string rather than hardcoded English, so other locales should work, but that
hasn't been tested. Other game versions haven't been tested either. If it
works — or doesn't — on yours, please
[open an issue](https://github.com/kokimoribe/wow-onlinecheck/issues).

### If every name comes back "Likely online"

The addon warns you when a run finds nothing unavailable at all. That can mean
everyone really is on, or it can mean the reply pattern doesn't match your
client's wording — it can't tell those apart.

Check a character you know is offline. If that one also reads *Likely online*,
run `/onlinecheck debug`, check them again, and include the raw line in an
issue.

## Development

    lua tests/test_onlinecheck.lua

The game client is the one place this can't be tested, so the control flow is
tested without it: a mock WoW API with a hand-fired timer queue, which lets a
test cancel a run *between* the last check and the settle callback.

Twenty-four cases, each one a way the addon could claim to know something it
doesn't: cancelling mid-run and mid-wait, an unexpected or throttled send
result, prefix registration returning any of several shapes, a reply with no
trailing period, server capitalisation, unrelated system messages, and messy
pasted input.
