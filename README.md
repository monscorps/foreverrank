# foreverrank.com

The race ladder for World of Warcraft: Forever — levelling, hardcore, PvP
and character progression, WarcraftLogs-style. Static site, no build step.

The addon is QuestBank (`tools/questbank/`, served at /questbank/), a free
questing addon for Forever. What it notes in game reaches the site when players
upload its saved file, by hand or with the optional Windows uploader
(`uploader/`), and goes into the next QuestBank release and the Database.

Also on the site: the Forge (planner), the Database (datamined beta client),
the Atlas, and /bis/ — best-in-slot lists per class and spec at levels 30 and
20, every slot ranked by the Forge's own scorer over our item database
(`node tools/build_bis.mjs` rebuilds bis/bis.json; its header says what a list
may hold).
Client tables come from wago.tools (`tools/fetch_wago.py BUILD`);
`tools/diff_builds.py` and the `tools/apply_*.py` scripts carry the data to a
new build, and SOURCES.md keeps the ledger of what came from where.
`support.js` is the sitewide feedback/donate corner card; its DONATE_URL points
at the PayPal link (empty hides the donate button).
