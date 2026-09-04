# CurseForge submission

Everything needed to publish, and the parts that still need a person.

## Listing

**Project icon** — [onlinecheck-logo.png](assets/onlinecheck-logo.png), a
1254 × 1254 PNG. Use this for the listing's project image. Selected design:
D, the refined green check.

**Name** — OnlineCheck
**Slug** — `onlinecheck` (confirmed unused, as is `online-check`)
**Categories** — Chat & Communication; Guild
**License** — MIT

**Summary**

> Paste a list of character names and check who's online.

**Description**

> OnlineCheck takes a list of character names and tells you which of them are
> reachable right now.
>
> Paste names one per line and click Check. Results group into **Likely
> online**, **Unavailable** and **Unknown**, and clicking one opens a whisper
> to that character — the addon never sends anything for you.
>
> Each check sends a hidden addon message to the character's client. No
> whisper is sent, and a client with no handler for that message discards it,
> so there is nothing for the player to see. If the character isn't reachable,
> the server replies with its standard "no player named" error.
>
> That makes **Unavailable** a positive observation and **Likely online** the
> absence of one: no offline reply arrived before the check finished. Good
> evidence, not a confirmation, and the addon says so rather than flattening
> it to "Online".
>
> It doesn't run `/who`, and doesn't show level, class, guild or zone.
>
> Developed and used on TBC Anniversary (2.5.6), English client. Other
> versions and locales are untested — reports welcome on GitHub.

## State

Live at <https://authors.curseforge.com/#/projects/1681279>, slug `onlinecheck`.
v1.0.3 uploaded by CI against game version 2.5.6 and is **Under Review** --
until a moderator approves it, the project is not visible to anyone else and
its files do not sync across CurseForge.

Configured: name, summary, description, logo, MIT licence, 3rd-party
distribution, class Addons, category Chat & Communication, and GitHub source
(`kokimoribe/wow-onlinecheck`). Automatic Packaging is deliberately off --
the release workflow builds the zip, and CurseForge's packager would fight it.

Still open, all optional:

- a screenshot for the listing -- use a run of 10-20 names, not two. The
  results list is 13 rows tall whether or not they are used, so a two-name
  check photographs as a mostly empty window and undersells the tool
- once approved, add the CurseForge install to README.md's Install section
  and put it first: auto-updates are the reason for publishing there, and
  the recruiting site's "Get the addon" link routes through that README
- additional category (Guild) -- where guild officers actually browse
- comments are off, so feedback arrives only as GitHub issues
- the display name is `onlinecheck`, lowercase, against `OnlineCheck`
  everywhere else. The slug is a separate field and would not change.

## Releasing

    # bump ## Version: in OnlineCheck/OnlineCheck.toc first -- CI enforces
    # that the tag and the TOC agree
    git tag v1.0.2 && git push --tags

The workflow runs the tests, refuses to package if the tag and TOC disagree,
builds a zip of the addon folder, checks it holds exactly the three expected
files (the two addon files plus the licence), publishes a GitHub release, and
uploads to CurseForge.

## Worth confirming after the first upload

Uploading successfully is not the same as the update path working, and the
update path is the reason for publishing here. After the first release lands,
install OnlineCheck through the CurseForge desktop app, push a version bump,
and check that the app offers it.
