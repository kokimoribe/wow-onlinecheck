# CurseForge submission

Everything needed to publish, and the parts that still need a person.

## Listing

**Name** — OnlineCheck
**Slug** — `onlinecheck` (confirmed unused, as is `online-check`)
**Categories** — Chat & Communication; Guild
**License** — MIT

**Summary**

> Paste a list of character names and check who's online.

**Description**

> OnlineCheck takes a list of character names and tells you which of them you
> can whisper right now, so you can find the few people worth talking to
> without typing `/who` once per name or filling your friends list with people
> you were only curious about.
>
> Paste names one per line, click Check, and the results group into **Likely
> online**, **Unavailable** and **Unknown**. Click a result to open a whisper
> to that character — the addon never sends anything for you.
>
> Each check sends a hidden addon message. Nothing reaches the player: no
> whisper is sent, and an addon message on a prefix their client doesn't
> handle is discarded silently. If the character isn't reachable, the server
> replies with its standard "no player named" error.
>
> That makes **Unavailable** a positive observation and **Likely online** an
> absence of one: no offline reply arrived before the check finished. It's
> good evidence, not a confirmation, and the addon says so rather than
> flattening it to "Online".
>
> It doesn't run `/who` and doesn't show level, class, guild or zone. It
> answers one question: can you whisper this person right now.
>
> Developed and used on TBC Anniversary (2.5.6), English client. Other
> versions and locales are untested — reports welcome on GitHub.

## Before the first upload

These need a person and can't be prepared here:

1. **Create the project** at <https://authors.curseforge.com> — choose World
   of Warcraft, paste the listing above, set the license to MIT, and link
   <https://github.com/kokimoribe/wow-onlinecheck> as the source.
2. **Note the numeric project ID** from the project page URL.
3. **Create an API token** at <https://legacy.curseforge.com/account/api-tokens>.
4. **Find the game-version ID** for TBC Anniversary 2.5.6:

       curl -s https://wow.curseforge.com/api/game/versions \
         -H "X-Api-Token: $CF_TOKEN" | jq '.[] | select(.name | test("2\\.5\\.6"))'

5. **Configure the repository** so the release workflow can upload:

   | where | name | value |
   |---|---|---|
   | Variable | `CURSEFORGE_PROJECT_ID` | the numeric project ID |
   | Variable | `CURSEFORGE_GAME_VERSION_ID` | the id from step 4 |
   | Secret | `CURSEFORGE_TOKEN` | the API token |

   Until `CURSEFORGE_PROJECT_ID` is set, the upload step is skipped and
   releases go to GitHub only.

6. **A screenshot** for the listing. The one showing a completed check, with
   one result Likely online and the rest Unavailable, makes the point better
   than any description.

## Releasing

    # bump ## Version: in OnlineCheck/OnlineCheck.toc first -- CI enforces
    # that the tag and the TOC agree
    git tag v1.0.1 && git push --tags

The workflow runs the tests, refuses to package if the tag and TOC disagree,
builds a zip containing only the addon folder, checks it holds exactly the two
expected files, publishes a GitHub release, and uploads to CurseForge if the
variables above are configured.
