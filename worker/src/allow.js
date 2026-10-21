/**
 * What may leave a player's PC: one allow-list for QuestBank.lua and Cute_Quest.lua alike
 * (docs/superpowers/specs/2026-10-21-cute-windows-design.md, 11.2 and 11.5). The same list is applied by the
 * uploader before it sends (uploader/QuestBank-Uploader.ps1), by the page's upload script, by the Worker before it
 * stores (this file), and by tools/probe_pull.py to every stored row as it reads it; probe_pull.py --selftest checks
 * the lists agree. Kept: the notes about the world (disc), the client's items and spells (game), the XP the game
 * showed (live, liveEra, turnins: times cut to the minute) and the client's diagnostics and errors (an error as its
 * message, where it was caught, its count and version). Everything else of the file stays on the PC: characters by
 * name, their bank, plans, travel, runs, settings, reports, the trace.
 *
 * Plain JavaScript with no imports, so the page can carry the same function.
 */
export const ALLOW = ['disc', 'game', 'live', 'liveEra', 'turnins', 'diag', 'errors'];
export const ERROR_KEYS = ['msg', 'where', 'count', 'version'];

const HEAD = /^\s*(QuestBankDB|CuteQuestDB)\s*=\s*\{/;
const TOKEN = /"(?:[^"\\]|\\.)*"|--[^\n]*|[{},]/g;
const KEY = /^\s*(?:--[^\n]*\n\s*)*\["([^"\\]*)"\]\s*=/;
const AT = /(\["at"\]\s*=\s*"\d{4}-\d{2}-\d{2} \d{2}:\d{2}):\d{2}"/g;
const ERROR_FIELD = new RegExp(
  '\\["(?!(?:' + ERROR_KEYS.join('|') + ')")[^"\\\\]*"\\]\\s*=\\s*(?:"(?:[^"\\\\]|\\\\.)*"|-?\\d+(?:\\.\\d+)?(?:[eE][-+]?\\d+)?|true|false|nil)\\s*,?',
  'g');

/** The top-level entries of the table a SavedVariables file assigns to QuestBankDB or CuteQuestDB:
 *  { name, entries: [{ key, text }] }, or null for any other file or one cut short. Strings and "--" comments are
 *  stepped over; the client ends every entry with a comma. */
export function savedEntries(text) {
  const m = HEAD.exec(text);
  if (!m) return null;
  const open = m.index + m[0].length - 1;
  let depth = 0, start = open + 1;
  const raw = [];
  TOKEN.lastIndex = open;
  for (let t; (t = TOKEN.exec(text)); ) {
    const v = t[0];
    if (v === '{') depth++;
    else if (v === '}') {
      if (--depth === 0) {
        const last = text.slice(start, t.index);
        if (last.trim()) raw.push(last);
        const entries = [];
        for (const e of raw) {
          const k = KEY.exec(e);
          if (k) entries.push({ key: k[1], text: e.trim() });
        }
        return { name: m[1], entries };
      }
    } else if (v === ',' && depth === 1) {
      raw.push(text.slice(start, t.index));
      start = t.index + 1;
    }
  }
  return null;
}

/** The file as it may be kept: the allow-list's entries only, in the file's order, hand-in times to the minute,
 *  errors without their stack or times. null when the text is no whole QuestBank or Cute_Quest file. */
export function stripSavedVariables(text) {
  const sv = savedEntries(text.replace(/^\uFEFF/, ''));
  if (!sv) return null;
  let out = sv.name + ' = {\n';
  for (const e of sv.entries) {
    if (!ALLOW.includes(e.key)) continue;
    let body = e.text;
    if (e.key === 'turnins') body = body.replace(AT, '$1"');
    if (e.key === 'errors') body = body.replace(ERROR_FIELD, '');
    out += '\t' + body + ',\n';
  }
  return out + '}\n';
}
