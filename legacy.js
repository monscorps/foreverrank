/* LegacyWindow: the in-game Legacy Tree window, shared by the Database and the Forge.
 * LegacyWindow(legacyData, { root, code, base, full, share, header, onApply }) -> { draw, code, spent, summary }
 * code is "digits-digits-digits", one digit per perk in data order. */
(function () {
  "use strict";
  var CDN = "https://wow.zamimg.com/images/wow/icons/large/";
  function esc(s) { return String(s == null ? "" : s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;"); }
  function img(n) {
    return '<img src="' + CDN + n + '.jpg" alt="" loading="lazy" onerror="this.onerror=null;this.src=\'' + CDN + 'inv_misc_questionmark.jpg\'">';
  }
  function sum(arr) { return arr.reduce(function (a, b) { return a + b; }, 0); }
  function copy(S) { return S.map(function (t) { return t.slice(); }); }

  window.LegacyWindow = function (lg, opts) {
    opts = opts || {};
    var root = opts.root, base = opts.base || "";
    var BUDGET = 16;
    var LAY = lg.layout || {};
    var RAIL = (lg.rail || lg.trees.map(function (t) { return t.name; })).map(function (n) {
      for (var i = 0; i < lg.trees.length; i++) if (lg.trees[i].name === n) return i;
      return -1;
    }).filter(function (i) { return i >= 0; });
    function zero() { return lg.trees.map(function (t) { return (t.perks || []).map(function () { return 0; }); }); }
    function decode(code) {
      var want = zero(), o = zero();
      if (!code) return o;
      String(code).split("-").forEach(function (seg, ti) {
        for (var i = 0; i < seg.length; i++) if (want[ti] && i < want[ti].length) want[ti][i] = Math.max(0, Math.min(+seg[i] || 0, lg.trees[ti].perks[i][1]));
      });
      // Replay the link through the same rules a click obeys: left columns first, so gates,
      // prerequisites and the 16-point cap all hold for old or hand-edited links.
      var order = [];
      lg.trees.forEach(function (t, ti) { t.perks.forEach(function (p, i) { var a = pos(ti, p[0]); order.push([a ? a[1] : 1, ti, i]); }); });
      order.sort(function (a, b) { return a[0] - b[0] || a[1] - b[1] || a[2] - b[2]; });
      for (var changed = true; changed;) {
        changed = false;
        order.forEach(function (x) {
          while (o[x[1]][x[2]] < want[x[1]][x[2]] && learnableIn(o, x[1], x[2])) { o[x[1]][x[2]]++; changed = true; }
        });
      }
      return o;
    }
    function spentAll(S) { return S.reduce(function (a, t) { return a + sum(t); }, 0); }
    function encode(S) { return spentAll(S) ? S.map(function (t) { return t.join(""); }).join("-") : ""; }
    var LG = decode(opts.code), ST = copy(LG);
    var SEL = (function () { for (var i = 0; i < lg.trees.length; i++) if (lg.trees[i].name === "Adventure") return i; return 0; })();
    var LQ = "";
    function staged() { return JSON.stringify(ST) !== JSON.stringify(LG); }
    function apply() { LG = copy(ST); if (opts.onApply) opts.onApply(encode(LG)); }
    function $q(sel) { return root.querySelector(sel); }

    function pos(ti, name) { var L = LAY[lg.trees[ti].name]; return L && L.nodes && L.nodes[name]; }
    function reqOf(ti, name) { var L = LAY[lg.trees[ti].name]; return L && L.req && L.req[name]; }
    function idxOf(ti, name) { var ps = lg.trees[ti].perks; for (var i = 0; i < ps.length; i++) if (ps[i][0] === name) return i; return -1; }
    function lockIn(S, ti, i) {
      var p = lg.trees[ti].perks[i], at = pos(ti, p[0]), pts = sum(S[ti]);
      if (at && at[1] > 1 && S[ti][i] === 0 && pts < 5) return "Requires 5 points in " + lg.trees[ti].name;
      var rq = reqOf(ti, p[0]);
      if (rq) {
        var ri = idxOf(ti, rq);
        if (ri >= 0 && S[ti][ri] < lg.trees[ti].perks[ri][1]) return "Requires " + rq;
      }
      return "";
    }
    function learnableIn(S, ti, i) { return !lockIn(S, ti, i) && S[ti][i] < lg.trees[ti].perks[i][1] && spentAll(S) < BUDGET; }
    function lockReason(ti, i) { return lockIn(ST, ti, i); }
    function canLearn(ti, i) { return learnableIn(ST, ti, i); }
    function canUnlearn(ti, i) {
      if (ST[ti][i] <= 0) return false;
      var name = lg.trees[ti].perks[i][0], myCol = (pos(ti, name) || [0, 1])[1];
      var trial = ST[ti].slice(); trial[i]--;
      for (var j = 0; j < trial.length; j++) {
        if (!trial[j] || j === i) continue;
        var pj = lg.trees[ti].perks[j], aj = pos(ti, pj[0]);
        if (reqOf(ti, pj[0]) === name) return false;
        if (aj && aj[1] > 1 && aj[1] > myCol) {
          var lower = 0;
          for (var k = 0; k < trial.length; k++) { var ak = pos(ti, lg.trees[ti].perks[k][0]); if (!ak || ak[1] < aj[1]) lower += trial[k]; }
          if (lower < 5) return false;
        }
      }
      return true;
    }
    function rankText(p, r) {
      var tpl = (lg.rankTpl || {})[p[0]];
      if (!tpl) return r <= 1 ? p[2] : null;
      return tpl.replace(/\{10-r\}/g, String(10 - r)).replace(/\{r\}/g, String(r));
    }
    function tipHTML(ti, i, touch) {
      var p = lg.trees[ti].perks[i], r = ST[ti][i], max = p[1];
      var shown = rankText(p, Math.max(1, r)) || p[2];
      var guessed = (r > 1 && !(lg.rankTpl || {})[p[0]]);
      var act = p[4] && p[4].active;
      var kind = act ? '<span class="lt-w lt-split"><i>' + esc(act[0]) + "</i><i>" + esc(act[1]) + "</i></span>" : '<span class="lt-w">Passive</span>';
      var h = "<b>" + esc(p[0]) + '</b><span class="lt-w">Rank ' + r + "/" + max + '</span><span class="lt-gap"></span>' +
        kind + '<p class="lt-y">' + esc(shown) + "</p>" +
        (guessed ? '<p class="lt-note">Rank 1 text; the demo never showed rank ' + r + ".</p>" : "");
      if (r > 0 && r < max) {
        var nx = rankText(p, r + 1);
        if (nx) h += '<span class="lt-gap"></span><span class="lt-w">Next Rank:</span>' + kind + '<p class="lt-y">' + esc(nx) + "</p>";
      }
      var why = lockReason(ti, i);
      if (why) h += '<em class="lt-r">' + esc(why) + "</em>";
      else if (r < max && spentAll(ST) < BUDGET) h += touch ? "" : '<em class="lt-g">Click to learn</em>';
      else if (r < max) h += '<em class="lt-r">No Legacy points left</em>';
      if (r > 0 && !touch) h += '<em class="lt-gr">Right click to unlearn</em>';
      var L = LAY[lg.trees[ti].name];
      if (L && (L.inferred || []).indexOf(p[0]) !== -1) h += '<p class="lt-note">Spot in the tree worked out from footage; no capture shows its tooltip on this node yet.</p>';
      return h;
    }
    function node(ti, i, style) {
      var p = lg.trees[ti].perks[i], r = ST[ti][i], why = lockReason(ti, i);
      var locked = why && r === 0;
      var lq = LQ.trim().toLowerCase();
      var q = lq && (p[0] + " " + p[2]).toLowerCase().indexOf(lq) !== -1;
      var cls = "lgn" + (locked ? " locked" : r >= p[1] ? " maxed" : " open") + (ST[ti][i] !== LG[ti][i] ? " staged" : "") + (q ? " hit" : "") + (lq && !q ? " dim" : "");
      return '<div class="' + cls + '"' + (style || "") + ' data-lgn="' + ti + ":" + i + '" data-tipkit="1">' +
        img(p[3] || "inv_misc_questionmark") + (locked ? "" : '<span class="lgn-r">' + r + "</span>") + "</div>";
    }
    var CELL = 3.3, GAP = 1.1;
    function at(rc) { return ' style="left:' + ((rc[1] - 1) * (CELL + GAP)) + "rem;top:" + ((rc[0] - 1) * (CELL + .8)) + 'rem"'; }
    function treePane(ti) {
      var t = lg.trees[ti], L = LAY[t.name] || { nodes: {}, placeholders: [], links: [], unknown: [] };
      var W = 4 * CELL + 3 * GAP, H = 4 * CELL + 3 * .8;
      function rcPoints(rc) {
        for (var k in (L.nodes || {})) if (L.nodes[k][0] === rc[0] && L.nodes[k][1] === rc[1]) { var ii = idxOf(ti, k); return ii >= 0 ? ST[ti][ii] : 0; }
        return 0;
      }
      var svg = '<svg class="lg-links" viewBox="0 0 ' + W + " " + H + '" preserveAspectRatio="none">' + (L.links || []).map(function (ln) {
        var a = ln[0], b = ln[1], lit = rcPoints(a) > 0 && rcPoints(b) > 0;
        var x1 = (a[1] - 1) * (CELL + GAP) + CELL / 2, y1 = (a[0] - 1) * (CELL + .8) + CELL / 2;
        var x2 = (b[1] - 1) * (CELL + GAP) + CELL / 2, y2 = (b[0] - 1) * (CELL + .8) + CELL / 2;
        return '<line' + (lit ? ' class="lit"' : "") + ' x1="' + x1 + '" y1="' + y1 + '" x2="' + x2 + '" y2="' + y2 + '"/>';
      }).join("") + "</svg>";
      var cells = "", tray = "";
      t.perks.forEach(function (p, i) {
        var rc = pos(ti, p[0]);
        if (rc) cells += node(ti, i, at(rc));
        else tray += node(ti, i, "");
      });
      (L.placeholders || []).forEach(function (rc) { cells += '<div class="lgn ph"' + at(rc) + ' data-lgph="1" data-tipkit="1"><span>?</span></div>'; });
      (L.unknown || []).forEach(function (rc) { cells += '<div class="lgn unk"' + at(rc) + ' data-lgunk="1" data-tipkit="1"><span></span></div>'; });
      return { grid: '<div class="lg-grid2" style="width:' + W + "rem;height:" + H + 'rem">' + svg + cells + "</div>", tray: tray };
    }
    function art(name) { var a = (lg.art || {})[name]; return a ? base + a : ""; }
    function windowHTML() {
      var avail = BUDGET - spentAll(ST), t = lg.trees[SEL], pane = treePane(SEL);
      var rail = RAIL.map(function (ti) {
        var lq = LQ.trim().toLowerCase();
        var tn = lg.trees[ti].name, hit = lq && lg.trees[ti].perks.some(function (p) { return (p[0] + " " + p[2]).toLowerCase().indexOf(lq) !== -1; });
        return '<button type="button" class="lg-port' + (ti === SEL ? " on" : "") + (hit ? " hit" : "") + '" data-lgsel="' + ti + '" title="' + esc(tn) + '">' +
          '<img src="' + esc(art(tn)) + '" alt=""><span class="lg-port-n">' + sum(ST[ti]) + "</span></button>";
      }).join("");
      var win = '<div class="lgwin">' +
        '<div class="lg-title"><span class="lg-emblem">' + img("inv_shield_06") + "</span>Legacy Tree" +
          (opts.onClose ? '<button type="button" class="lg-close" data-lgclose="1" aria-label="Close">&times;</button>' : "") + "</div>" +
        '<div class="lg-bar"><span class="lg-crown" title="Legacy points this character may spend at launch">' + BUDGET + "</span>" +
          '<span class="lg-avail" data-tipkit="1" data-lgavail="1">Available points: <b>' + avail + " LP</b></span>" +
          '<input class="lg-search" data-lgq="1" type="search" placeholder="Search" value="' + esc(LQ) + '"></div>' +
        '<div class="lg-body"><div class="lg-rail">' + rail + "</div>" +
          '<div class="lg-main"><div class="lg-hero"><span class="lg-tname">' + esc(t.name) + "</span>" +
            '<div class="lg-big lg-art-' + esc(t.name.toLowerCase()) + '"><img src="' + esc(art(t.name)) + '" alt=""><span class="lg-big-n">' + sum(ST[SEL]) + "</span></div></div>" +
            pane.grid + "</div></div>" +
        '<div class="lg-foot"><button type="button" class="lg-apply" data-lgapply="1"' + (staged() ? "" : " disabled") + ">Apply Changes</button>" +
          '<button type="button" class="lg-undo" data-lgundo="1"' + (staged() ? "" : " disabled") + ' title="Undo staged changes">' + (staged() ? "↺" : "⊘") + "</button></div></div>";
      var under = (pane.tray ? '<div class="lg-tray"><span>In the ' + esc(t.name) + " tree, spot not yet pinned from footage:</span><div>" + pane.tray + "</div></div>" : "") +
        '<div class="lg-actions">' + (opts.share ? '<button type="button" class="share" data-lgshare="1">Share legacy build</button>' : "") +
        '<button type="button" class="share" data-lgreset="1">Unlearn everything</button>' +
        (opts.onClose ? '<button type="button" class="share lg-done" data-lgdone="1">Done</button>' : "") +
        '<span class="lg-sum">' + lg.trees.map(function (tt, ti) { return esc(tt.name) + " " + sum(LG[ti]); }).join(" · ") + "</span></div>" +
        (opts.full ? '<p class="board-sub">Click to learn, right-click to unlearn, then Apply Changes, like the game. On a phone, tap a perk for its tooltip and Learn/Unlearn buttons. ' +
          esc(lg.tierRule || "") + " " + esc(lg.treeNote) + "</p>" + rewardTrack() : "");
      return win + under;
    }
    function rewardTrack() {
      if (!lg.rewards) return "";
      var MAXP = 65;
      return '<div class="lg-reward"><div class="lg-rw-head"><b>Legacy Reward Track</b><span>' + esc(lg.rewardsNote || "") + "</span></div>" +
        '<div class="lg-rw-bar"><div class="lg-rw-fill" style="width:' + Math.round(16 / MAXP * 100) + '%"></div>' +
        '<span class="lg-rw-cap" style="left:' + (16 / MAXP * 100) + '%" title="Seasonal spend cap">16 cap</span>' +
        lg.rewards.map(function (rw, ri) {
          return '<div class="lg-rw-pt" style="left:' + (rw[0] / MAXP * 100) + '%" data-tipkit="1" data-rw="' + ri + '">' + img(rw[2]) + "<em>" + rw[0] + "</em></div>";
        }).join("") + '<span class="lg-rw-end">65</span></div>' +
        (lg.challenges ? '<p class="lg-rw-cats"><b>Challenge categories:</b> ' + esc(lg.challenges.join(" · ")) + "</p>" : "") + "</div>";
    }
    function hideTip() { if (window.TipKit) TipKit.hide(); }
    function after(ti, i) {
      draw();
      if (TipKit.sheetOpen()) sheet(ti, i);
      else if (!TipKit.touchy()) TipKit.show(tipHTML(ti, i, false), "lgtip", null, root.querySelector('[data-lgn="' + ti + ":" + i + '"]'));
    }
    function sheet(ti, i) {
      var p = lg.trees[ti].perks[i];
      TipKit.openSheet(tipHTML(ti, i, true), [
        { label: "Unlearn −", cls: "unlearn", disabled: !canUnlearn(ti, i), onClick: function () { if (canUnlearn(ti, i)) { ST[ti][i]--; after(ti, i); } } },
        { label: ST[ti][i] + " / " + p[1], cls: "count", disabled: true },
        { label: "Learn +", cls: "learn", disabled: !canLearn(ti, i), onClick: function () { if (canLearn(ti, i)) { ST[ti][i]++; after(ti, i); } } }
      ], { cls: "lgsheet", owner: "lg:" + ti + ":" + i });
    }
    var PH_HTML = '<b>Unknown</b><span class="lt-w">Passive</span><p class="lt-y">To be added in future patch content.</p>';
    var UNK_HTML = '<b>Unidentified node</b><p class="lt-y">A real perk sits here in the demo, but the footage never hovered it, so its name is not pinned yet.</p>';
    function infoTip(n, html) {
      TipKit.hover(n, function () { return html; }, function () { return "lgtip"; }, { anchor: true });
      n.addEventListener("click", function () { if (TipKit.touchy()) TipKit.openSheet(html, [], { cls: "lgsheet" }); });
    }
    function draw() {
      hideTip();
      root.innerHTML = (opts.header || "") + windowHTML();
      root.querySelectorAll("[data-lgn]").forEach(function (n) {
        var pr = n.getAttribute("data-lgn").split(":"), ti = +pr[0], i = +pr[1];
        TipKit.hover(n, function () { return tipHTML(ti, i, false); }, function () { return "lgtip"; }, { anchor: true });
        n.addEventListener("click", function (e) {
          if (TipKit.touchy()) { sheet(ti, i); return; }
          if (!canLearn(ti, i)) return;
          do { ST[ti][i]++; } while (e.shiftKey && canLearn(ti, i));
          after(ti, i);
        });
        n.addEventListener("contextmenu", function (e) {
          e.preventDefault();
          if (TipKit.touchy()) { sheet(ti, i); return; }
          if (!canUnlearn(ti, i)) return;
          do { ST[ti][i]--; } while (e.shiftKey && canUnlearn(ti, i));
          after(ti, i);
        });
      });
      var avt = $q("[data-lgavail]");
      if (avt) infoTip(avt, '<p class="lt-y lt-plain">' + esc(lg.availTip || "") + "</p>");
      root.querySelectorAll("[data-rw]").forEach(function (n) {
        var rw = lg.rewards[+n.getAttribute("data-rw")];
        infoTip(n, "<b>" + esc(rw[1]) + '</b><span class="lt-w">' + esc(rw[3]) + '</span><p class="lt-y">Unlocks at ' + rw[0] + " Legacy points earned on the account.</p>");
      });
      root.querySelectorAll("[data-lgph]").forEach(function (n) { infoTip(n, PH_HTML); });
      root.querySelectorAll("[data-lgunk]").forEach(function (n) { infoTip(n, UNK_HTML); });
      root.querySelectorAll("[data-lgsel]").forEach(function (b) {
        b.addEventListener("click", function () { SEL = +b.getAttribute("data-lgsel"); draw(); });
      });
      var q = $q("[data-lgq]");
      if (q) q.addEventListener("input", function () {
        LQ = q.value;
        var caret = q.selectionStart; draw();
        var q2 = $q("[data-lgq]"); if (q2) { q2.focus(); try { q2.setSelectionRange(caret, caret); } catch (e) {} }
      });
      var ap = $q("[data-lgapply]");
      if (ap) ap.addEventListener("click", function () { apply(); draw(); });
      var un = $q("[data-lgundo]");
      if (un) un.addEventListener("click", function () { ST = copy(LG); draw(); });
      var rs = $q("[data-lgreset]");
      if (rs) rs.addEventListener("click", function () { ST = zero(); draw(); });
      var sh = $q("[data-lgshare]");
      if (sh) sh.addEventListener("click", function () {
        if (staged()) { apply(); draw(); sh = $q("[data-lgshare]"); }
        var url = location.href;
        function done() { sh.textContent = "Link copied"; setTimeout(function () { sh.textContent = "Share legacy build"; }, 1600); }
        if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(url).then(done, function () { prompt("Copy this:", url); });
        else prompt("Copy this:", url);
      });
      var dn = $q("[data-lgdone]");
      if (dn) dn.addEventListener("click", close);
      var cl = $q("[data-lgclose]");
      if (cl) cl.addEventListener("click", close);
    }
    function close() {
      if (staged()) apply();
      hideTip();
      if (window.TipKit) TipKit.closeSheet();
      if (opts.onClose) opts.onClose();
    }
    function summary() {
      return lg.trees.map(function (t, ti) {
        return { tree: t.name, points: sum(LG[ti]), perks: t.perks.map(function (p, i) { return LG[ti][i] ? p[0] + " " + LG[ti][i] + "/" + p[1] : null; }).filter(Boolean) };
      });
    }
    return { draw: draw, code: function () { return encode(LG); }, spent: function () { return spentAll(LG); }, summary: summary,
      setCode: function (c) { LG = decode(c); ST = copy(LG); }, close: close, budget: BUDGET };
  };
})();
