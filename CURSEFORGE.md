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

## What is left

Steps 1 and 2 are done: the project exists at
<https://authors.curseforge.com/#/projects/1681279>, and
`CURSEFORGE_PROJECT_ID` is set to `1681279`.

Two things still need a person:

1. **Create an API token** at <https://legacy.curseforge.com/account/api-tokens>
   and add it as a repository secret named `CURSEFORGE_TOKEN`:

       gh secret set CURSEFORGE_TOKEN --repo kokimoribe/wow-onlinecheck

   Paste it at the prompt, so the token never lands in shell history.

   Until this is set, the upload step warns and skips, and releases go to
   GitHub only. It does not fail the release.

2. **Add a screenshot** to the listing. The one showing a completed check,
   with one result Likely online and the rest Unavailable, makes the point
   better than any description.

The game-version ID is no longer something to look up by hand — the workflow
resolves `2.5.6` to its numeric ID at upload time and stops if the name
matches zero or several versions, printing the candidates. To pin one
instead, set the `CURSEFORGE_GAME_VERSION_ID` variable; to build against a
different client, set `CURSEFORGE_GAME_VERSION` to its name.

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
