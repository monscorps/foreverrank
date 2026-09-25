/* Spec rankings: estimates grouped into tiers, plus what the BlizzCon demo
 * meters actually showed. Reads /codex/rankings.json; no framework. */
(function () {
  "use strict";

  var ICON = "https://wow.zamimg.com/images/wow/icons/large/";
  var CLASS_COLOUR = {
    Warrior: "#c79c6e", Paladin: "#f58cba", Hunter: "#abd473", Rogue: "#fff569", Priest: "#ffffff",
    Shaman: "#0070de", Mage: "#69ccf0", Warlock: "#9482c9", Druid: "#ff7d0a"
  };
  // Tiers wear the item-quality colours players already read at a glance.
  var TIERS = [
    { t: "S", min: 85, c: "var(--q-legendary)", d: "85 and up" },
    { t: "A", min: 75, c: "var(--q-epic)", d: "75 to 84" },
    { t: "B", min: 65, c: "var(--q-rare)", d: "65 to 74" },
    { t: "C", min: 55, c: "var(--q-uncommon)", d: "55 to 64" },
    { t: "D", min: 0, c: "var(--q-common)", d: "below 55" }
  ];
  var CONF = { low: 1, medium: 2, high: 3 };

  function $(id) { return document.getElementById(id); }
  function esc(s) { return String(s == null ? "" : s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;"); }
  function clsIcon(cls) { return ICON + "classicon_" + cls.toLowerCase() + ".jpg"; }
  function when(d) {
    var dt = new Date(d + "T12:00:00Z");
    return isNaN(dt) ? d : dt.toLocaleDateString("en-GB", { day: "numeric", month: "short" });
  }

  var role = "dps", lvl = "30", data = null;

  function pips(conf) {
    var n = CONF[conf] || 1, out = "";
    for (var i = 1; i <= 3; i++) out += "<i" + (i <= n ? ' class="on"' : "") + "></i>";
    return '<span class="cf" title="' + esc(conf) + ' confidence">' + out + "</span>";
  }
  function row(e, unit) {
    var tags = "";
    if (e.pulse && (e.pulse.strong || e.pulse.weak)) {
      tags += '<span class="tg" title="What demo players said about this spec">' +
        (e.pulse.strong ? '<b class="up">▲ ' + e.pulse.strong + " strong</b>" : "") +
        (e.pulse.weak ? '<b class="dn">▼ ' + e.pulse.weak + " weak</b>" : "") + "</span>";
    }
    if (e.meas && e.meas.samples) {
      tags += '<span class="tg mt" title="Damage meter rows read from the BlizzCon demo">' + e.meas.samples + " demo meter " +
        (e.meas.samples === 1 ? "reading" : "readings") + (e.meas.avg ? ", about " + e.meas.avg + " " + unit : "") + "</span>";
    }
    return '<li class="rk-row" tabindex="0" style="--cc:' + (CLASS_COLOUR[e.cls] || "#fff") + '">' +
      '<span class="rk-n">' + e.rank + "</span>" +
      '<span class="rk-ic"><img src="' + ICON + esc(e.icon) + '.jpg" alt="" loading="lazy"><img class="rk-cl" src="' + clsIcon(e.cls) + '" alt="" loading="lazy"></span>' +
      '<span class="rk-t"><b>' + esc(e.spec) + " <i>" + esc(e.cls) + "</i></b><em>" + esc(e.why) + "</em>" +
      (tags ? '<span class="rk-tags">' + tags + "</span>" : "") + "</span>" +
      '<span class="rk-sc"><span class="rk-meter"><i style="width:' + e.score + '%"></i></span><b>' + e.score + "</b>" + pips(e.conf) + "</span></li>";
  }
  function drawBoard() {
    var list = (data.lists[role + "_" + lvl] || []).slice().sort(function (a, b) { return a.rank - b.rank; });
    var unit = role === "heal" ? "hps" : "dps";
    var html = TIERS.map(function (t, i) {
      var max = i ? TIERS[i - 1].min : 1e9;
      var rows = list.filter(function (e) { return e.score >= t.min && e.score < max; });
      if (!rows.length) return "";
      return '<div class="tier" style="--t:' + t.c + '"><div class="tier-h"><b>' + t.t + "</b><span>" + t.d + "</span></div>" +
        '<ol class="rk-list">' + rows.map(function (e) { return row(e, unit); }).join("") + "</ol></div>";
    }).join("");
    $("rk-board").innerHTML = html || '<p class="rk-none">No estimates for this view yet.</p>';
    $("rk-count").textContent = list.length + (list.length === 1 ? " spec" : " specs") + " · " + (role === "heal" ? "healing" : "damage") + " at level " + lvl;
    Array.prototype.forEach.call(document.querySelectorAll("#rk-role button, #rk-lvl button"), function (b) {
      var on = b.getAttribute("data-role") === role || b.getAttribute("data-lvl") === lvl;
      b.classList.toggle("on", on);
      b.setAttribute("aria-checked", String(on));
    });
    var q = role + "_" + lvl === "dps_30" ? location.pathname : "?view=" + role + "_" + lvl;
    try { history.replaceState(null, "", q + location.hash); } catch (e) {}
  }
  function drawMeters() {
    var m = (data.meters || []).slice().sort(function (a, b) { return (b.avgDps || 0) - (a.avgDps || 0); });
    if (!m.length) { $("rk-meters").hidden = true; return; }
    var top = m[0].avgDps || 1;
    $("rk-meter-list").innerHTML = m.map(function (r) {
      var colour = CLASS_COLOUR[r.cls] || "#fff";
      return '<li style="--cc:' + colour + '"><img src="' + clsIcon(r.cls) + '" alt="" loading="lazy">' +
        '<span class="mt-n"><b>' + esc(r.cls) + "</b><small>" + esc(r.spec || r.role) + "</small></span>" +
        '<span class="mt-bar"><i style="width:' + Math.round((r.avgDps || 0) / top * 100) + '%"></i></span>' +
        '<span class="mt-v"><b>' + (r.avgDps == null ? "?" : r.avgDps) + "</b> dps</span>" +
        '<span class="mt-m">' + r.samples + " readings · " + r.players + (r.players === 1 ? " player" : " players") +
        (r.topShare != null ? " · top of the meter in " + Math.round(r.topShare * 100) + "% of fights" : "") + "</span></li>";
    }).join("");
  }
  function drawQuotes() {
    var q = data.quotes || [];
    if (!q.length) { $("rk-quotes").hidden = true; return; }
    $("rk-quote-list").innerHTML = q.map(function (x) {
      var known = CLASS_COLOUR[x.cls];
      return '<figure style="--cc:' + (known || "#e5cc80") + '">' +
        (known ? '<img src="' + clsIcon(x.cls) + '" alt="" loading="lazy">' : '<span class="q-any">?</span>') +
        "<blockquote>“" + esc(x.quote) + "”</blockquote>" +
        "<figcaption><b>" + esc(x.who) + "</b>" + esc(x.where) + " · " + when(x.date) +
        (known ? ' · <span style="color:' + known + '">' + esc((x.spec ? x.spec + " " : "") + x.cls) + "</span>" : "") + "</figcaption></figure>";
    }).join("");
  }

  document.addEventListener("DOMContentLoaded", function () {
    var v = (new URLSearchParams(location.search).get("view") || "").split("_");
    if (v[0] === "dps" || v[0] === "heal") role = v[0];
    if (v[1] === "30" || v[1] === "60") lvl = v[1];
    $("rk-role").addEventListener("click", function (e) {
      var b = e.target.closest("button[data-role]");
      if (b && data) { role = b.getAttribute("data-role"); drawBoard(); }
    });
    $("rk-lvl").addEventListener("click", function (e) {
      var b = e.target.closest("button[data-lvl]");
      if (b && data) { lvl = b.getAttribute("data-lvl"); drawBoard(); }
    });
    // A tap opens a row's full reasoning; the list shows two lines of it.
    $("rk-board").addEventListener("click", function (e) {
      var r = e.target.closest(".rk-row");
      if (r) r.classList.toggle("open");
    });
    $("rk-board").addEventListener("keydown", function (e) {
      if ((e.key === "Enter" || e.key === " ") && e.target.classList.contains("rk-row")) { e.preventDefault(); e.target.classList.toggle("open"); }
    });
    fetch("/codex/rankings.json", { cache: "no-store" }).then(function (r) { return r.ok ? r.json() : null; }).catch(function () { return null; }).then(function (d) {
      if (!d || !d.lists) { $("rk-board").innerHTML = '<p class="rk-none">The estimates could not load. Refresh to try again.</p>'; return; }
      data = d;
      drawBoard();
      drawMeters();
      drawQuotes();
    });
  });
})();
