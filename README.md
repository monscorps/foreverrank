# foreverrank.com

The race ladder for World of Warcraft: Forever — levelling, hardcore, PvP
and character progression, WarcraftLogs-style. Static site, no build step.

The addon is QuestBank (`tools/questbank/`, served at /questbank/), a free
questing addon for Forever. What it notes in game reaches the site when players
upload its saved file, by hand or with the optional Windows uploader
(`uploader/`), and goes into the next QuestBank release and the Database.

Also on the site: the Forge (planner), the Database (datamined beta client),
the Atlas, and /bis/ — best-in-slot lists per class and spec at the beta cap,
slot rankings compiled from ForeverChanges (see SOURCES.md), every cited
item's tooltip read fresh from the current build at compile time, with our own
item datamine as backstop. `tools/build_bis.py` then `tools/build_bis_items.py`
refresh them (delete tools/.bis-cache/ first for a truly fresh pull).
`support.js` is the sitewide feedback/donate corner card; set its DONATE_URL
when there is somewhere for coins to go.
