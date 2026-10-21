// Tests for the Worker's upload and finds endpoints, run with: node worker/test.mjs (Node 18 or later; nothing is
// deployed, D1 is a stand-in that understands the few statements these endpoints make). Exits 1 on a failed check.
import worker, { findsProblem } from './src/index.js';
import { ALLOW, stripSavedVariables } from './src/allow.js';

let checks = 0, fails = 0;
function check(name, cond) {
  checks++;
  if (cond) console.log('  ok    ' + name);
  else { fails++; console.log('  FAIL  ' + name); }
}

// a D1 stand-in: probe_uploads, the rate limiter's audit rows, finds_data
class Stmt {
  constructor(db, sql) { this.db = db; this.sql = sql; this.args = []; }
  bind(...a) { this.args = a; return this; }
  async first() {
    const s = this.sql, d = this.db;
    if (s.startsWith('SELECT COUNT(*) AS n FROM audit')) return { n: 0 };
    if (s.startsWith('SELECT id, received FROM probe_uploads WHERE hash')) return d.uploads.find((r) => r.hash === this.args[0]) || null;
    if (s.startsWith('SELECT body, updated FROM finds_data')) {
      if (!d.findsTable) throw new Error('D1_ERROR: no such table: finds_data');
      return d.finds;
    }
    throw new Error('unexpected first: ' + s);
  }
  async run() {
    const s = this.sql, d = this.db;
    if (s.startsWith('INSERT INTO audit')) return { meta: {} };
    if (s.startsWith('INSERT INTO probe_uploads')) {
      const [received, ipHash, source, kind, filename, size, hash, summary, body] = this.args;
      d.uploads.push({ id: d.uploads.length + 1, received, source, kind, filename, size, hash, summary, body });
      return { meta: { last_row_id: d.uploads.length } };
    }
    if (s.startsWith('CREATE TABLE IF NOT EXISTS finds_data')) { d.findsTable = true; return { meta: {} }; }
    if (s.startsWith('INSERT INTO finds_data')) { d.finds = { body: this.args[0], updated: this.args[1] }; return { meta: {} }; }
    throw new Error('unexpected run: ' + s);
  }
}
class DB {
  constructor() { this.uploads = []; this.finds = null; this.findsTable = false; }
  prepare(sql) { return new Stmt(this, sql); }
}
const env = { DB: new DB(), PROBE_ADMIN_KEY: 'test-admin-key' };
const base = 'https://worker.test';
async function call(path, init = {}) {
  const res = await worker.fetch(new Request(base + path, init), env, { waitUntil() {} });
  let body = null;
  try { body = await res.json(); } catch { body = null; }
  return { status: res.status, body };
}
async function upload(text, filename) {
  const fd = new FormData();
  fd.append('source', 'uploader');
  fd.append('file', new Blob([text], { type: 'text/plain' }), filename);
  return call('/api/probe', { method: 'POST', body: fd });
}
async function stored(id) {
  const row = env.DB.uploads[id - 1];
  const ds = new DecompressionStream('gzip');
  const w = ds.writable.getWriter();
  w.write(new Uint8Array(row.body));
  w.close();
  return await new Response(ds.readable).text();
}

const full = (name) => `${name} = {
	["chars"] = {
		["Helga-ForeverNormal"] = {
			["level"] = 20,
		},
	},
	["disc"] = {
		["v"] = 1,
		["q"] = {
			[33] = {
				["t"] = "Wolves Across the Border",
			},
		},
		["note"] = "a } and a , inside",
	},
	["errors"] = {
		{
			["msg"] = "Interface/AddOns/QuestBank/Finds.lua:12: oops",
			["stack"] = "Helga's stack",
			["where"] = "finds",
			["first"] = "2026-10-22 18:04:31",
			["count"] = 2,
		}, -- [1]
	},
	["settings"] = {
		["welcome"] = "done",
	},
	["turnins"] = {
		{
			["id"] = 300,
			["at"] = "2026-10-22 18:04:31",
		}, -- [1]
	},
	["travel"] = {
		["gPlayer-1-0001"] = {
		},
	},
}
`;

console.log('=== the allow-list');
check('the list', JSON.stringify(ALLOW) === JSON.stringify(['disc', 'game', 'live', 'liveEra', 'turnins', 'diag', 'errors']));
const cut = stripSavedVariables(full('QuestBankDB'));
console.log(cut.split('\n').map((l) => '  | ' + l).join('\n'));
check('only the allowed parts, in the file\'s order', [...cut.matchAll(/^\t\["(\w+)"\] = /gm)].map((m) => m[1]).join(',') === 'disc,errors,turnins');
check('no name past it', !cut.includes('Helga'));
check('a string with a brace and a comma read whole', cut.includes('"a } and a , inside"'));
check('hand-in times to the minute', cut.includes('["at"] = "2026-10-22 18:04",') && !cut.includes('18:04:31'));
check('an error keeps message, where and count, never its stack or times', cut.includes('Finds.lua:12: oops') && cut.includes('["count"] = 2') && !cut.includes('stack') && !cut.includes('first'));
check('a file cut short is none', stripSavedVariables('QuestBankDB = {\n["disc"] = {\n') === null);
check('another file is none', stripSavedVariables('ForeverProbeDB = {\n}\n') === null);

console.log('=== uploads');
let r = await upload(full('CuteQuestDB'), 'Cute_Quest.lua');
check('a Cute_Quest.lua is taken: ' + JSON.stringify(r.body), r.status === 200 && r.body.ok && r.body.kind === 'cutequest-savedvars' && r.body.summary.quests === 1);
let kept = await stored(r.body.id);
check('stored cut to the allow-list', kept.startsWith('CuteQuestDB = {') && !kept.includes('Helga') && !kept.includes('settings') && kept.includes('["disc"]'));
r = await upload('CuteDB = {\n["roster"] = {\n["Helga"] = {\n},\n},\n}\n', 'Cute.lua');
check('a Cute.lua is refused: ' + JSON.stringify(r.body), r.status === 400 && /never accepted/.test(r.body.error) && env.DB.uploads.length === 1);
r = await upload(full('QuestBankDB'), 'QuestBank.lua');
check('a QuestBank.lua the page sends whole is stored cut', r.status === 200 && r.body.kind === 'questbank-savedvars' && !(await stored(r.body.id)).includes('Helga'));
r = await upload(full('QuestBankDB').replace('["level"] = 20', '["level"] = 21'), 'QuestBank.lua');
check('the same file but for a dropped part is a duplicate once cut', r.status === 200 && r.body.duplicate === true && env.DB.uploads.length === 2);
r = await upload('QuestBankDB = {\n["disc"] = {\n', 'QuestBank.lua');
check('a file cut short is refused', r.status === 400 && /cut short/.test(r.body.error));
r = await upload('FPROBE2:{"snapshots":[],"meta":{"addon":"0.4.8"}}', 'export.txt');
check('an old ForeverProbe export is still taken as it is', r.status === 200 && r.body.kind === 'export');

console.log('=== the finds');
r = await call('/api/finds.json');
check('none published: an empty set dated today', r.status === 200 && r.body.v === 1 && Array.isArray(r.body.rows) && r.body.rows.length === 0 && r.body.at > 20260000);
const set = { v: 1, at: 20261022, rows: [[1429, 'b', 0, '412,654', 2, "Archmage Theocritus' Research Journal"], [1435, 'k', 424080, '605,223', 3, 216523],
  [1429, 'h', 2843, '413,655;100,200', 2, '7.5'], [1438, 'r', 6582, '303,298', 2, 35]] };
r = await call('/api/finds', { method: 'POST', body: JSON.stringify(set) });
check('publishing needs the admin key', r.status === 401);
for (const [bad, why] of [[{ ...set, code: 'os.exit()' }, 'a field outside'], [{ ...set, v: 2 }, 'version'], [{ ...set, rows: [[1429, 'x', 1, '1,1', 2, 5]] }, 'kind'],
  [{ ...set, rows: [[1429, 'b', 1, '1,1', 2, '|cffRed|r']] }, 'title'], [{ ...set, rows: [[1429, 'h', 1, '1,1', 2, 'os.exit()']] }, 'items'],
  [{ ...set, rows: [[1429, 'k', '1', '1,1', 2, 5]] }, 'number'], [{ ...set, rows: [[1429, 'b', 1, '1,1;x', 2, 't']] }, 'spot']]) {
  r = await call('/api/finds', { method: 'POST', headers: { 'x-admin-key': 'test-admin-key' }, body: JSON.stringify(bad) });
  check('refused, ' + why + ': ' + (r.body && r.body.error), r.status === 400 && findsProblem(bad) !== null);
}
r = await call('/api/finds', { method: 'POST', headers: { 'x-admin-key': 'test-admin-key' }, body: JSON.stringify(set) });
check('a good set is stored', r.status === 200 && r.body.rows === 4);
r = await call('/api/finds.json');
check('and served as published', r.status === 200 && JSON.stringify(r.body) === JSON.stringify(set));

console.log(`\n${checks - fails} of ${checks} checks passed`);
if (fails) process.exit(1);
