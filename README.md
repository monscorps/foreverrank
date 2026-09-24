# foreverrank.com

The race ladder for World of Warcraft: Forever — levelling, hardcore, PvP
and character progression, WarcraftLogs-style. Static site, no build step.
The measurement addon lives with its 3.3.5a sibling until the Forever beta
reveals the addon API: https://github.com/monscorps/levelpace

Also on the site: the Forge (planner), the Database (datamined beta client),
the Atlas, and /bis/ — best-in-slot lists per class and spec at the beta cap,
slot rankings compiled from ForeverChanges (see SOURCES.md), every cited
item's tooltip read fresh from the current build at compile time, with our own
item datamine as backstop. `tools/build_bis.py` then `tools/build_bis_items.py`
refresh them (delete tools/.bis-cache/ first for a truly fresh pull).
`support.js` is the sitewide feedback/donate corner card; set its DONATE_URL
when there is somewhere for coins to go.
