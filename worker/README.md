# The ForeverRank Worker

`src/index.js` is the Cloudflare Worker behind foreverrank.com's API (`wrangler.jsonc`: the `foreverrank` Worker and its
D1 database). Only the owner deploys it; nothing in the repository's tools does.

## Test before deploying

    node worker/test.mjs

Node 18 or later, no network and no wrangler: D1 is a stand-in. It checks the allow-list (`src/allow.js`), that a
`Cute_Quest.lua` is taken and stored cut to it, that a `Cute.lua` is refused, and the finds endpoints.
`python3 tools/probe_pull.py --selftest` checks that `src/allow.js`, the uploader and `probe_pull.py` keep the same list.

## Deploying the finds round (QuestBank 6.2, Cute's uploader)

The QuestBank page on this round asks for `Cute_Quest.lua` (the upload box cuts it to the allow-list), which only this
Worker takes: the one live before it answers every `Cute_Quest.lua` with 400 "not a QuestBank.lua file". Pages publishes
main on push, and this Worker goes live only by the owner's deploy, so the release goes in this order:

1. Deploy the Worker (the deploy, below) and check `/api/finds.json` answers.
2. Rebuild the uploaders from `uploader/` as it is now: `python3 tools/build_uploader.py` (QuestBank-Uploader.zip,
   which reads `Cute_Quest.lua` too) and `python3 tools/build_uploader.py --cute` (Cute-Uploader.zip, for Cute's page).
3. `python3 -I tools/questbank/build_page.py --online`: it stops while the zip does not read `Cute_Quest.lua` or the
   live Worker has no finds round.
4. Only then push main.

The deploy:

1. `cd worker && npx wrangler deploy` (the code: the `cutequest-savedvars` kind, Cute.lua refused, every QuestBank.lua and
   Cute_Quest.lua cut to the allow-list before it is stored, `GET /api/finds.json`, `POST /api/finds`).
2. The `finds_data` table is created on the first publish; to make it by hand:
   `npx wrangler d1 execute levelpace-forever --remote --command "CREATE TABLE IF NOT EXISTS finds_data (id INTEGER PRIMARY KEY CHECK (id = 1), body TEXT NOT NULL, updated INTEGER NOT NULL)"`.
3. `python3 tools/probe_pull.py` as usual (it pulls, merges and writes `research/questbank/finds.json`), then
   `python3 tools/probe_pull.py --publish-finds` sends that file to `POST /api/finds` with the admin key
   (`worker/.probe-admin-key` or `PROBE_ADMIN_KEY`). Until the first publish, `/api/finds.json` answers an empty set
   dated today, which the uploader writes and asks again for the next day.
4. Check: `curl https://foreverrank.andustemme.workers.dev/api/finds.json` shows `{"v":1,"at":...,"rows":[...]}`.

Rows stored before the allow-list keep the parts it drops (characters by name, travel, runs): `probe_pull.py` cuts them
as it reads them. They are kept until after launch; then, owner-run, `disc.flown` is backfilled from their `travel`,
their `runs` exported for the run-times round, and only then are the dropped parts purged from D1.
