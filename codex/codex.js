/* The Codex: renders codex.json. Icons hotlinked like everywhere else. */
(function () {
  "use strict";
  var CDN = "https://wow.zamimg.com/images/wow/icons/large/";
  var CLASS_COLOUR = { Warrior: "#c79c6e", Paladin: "#f58cba", Hunter: "#abd473", Rogue: "#fff569",
    Priest: "#ffffff", Shaman: "#0070de", Mage: "#69ccf0", Warlock: "#9482c9", Druid: "#ff7d0a" };
  function esc(s) { return String(s == null ? "" : s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }
  function img(n) {
    return '<img src="' + CDN + n + '.jpg" alt="" loading="lazy" onerror="this.onerror=null;this.src=\'' + CDN + 'inv_misc_questionmark.jpg\'">';
  }
  function facts(list) {
    return '<ul class="facts">' + list.map(function (f) { return "<li>" + esc(f) + "</li>"; }).join("") + "</ul>";
  }

  fetch("codex.json", { cache: "no-store" }).then(function (r) { return r.json(); }).then(function (d) {
    var out = [], nav = [];
    function section(id, title, html) {
      nav.push('<a href="#' + id + '">' + title + "</a>");
      out.push('<section id="' + id + '"><h2>' + title + "</h2>" + html + "</section>");
    }

    // Legacy
    var lg = d.legacy;
    var trees = lg.trees.map(function (t) {
      return "<h3>" + img(t.icon) + " " + esc(t.name) + "</h3><div class=\"perks\">" +
        (t.perks || []).map(function (p) {
          return '<div class="perk">' + img(p[3] || "inv_misc_questionmark") +
            "<div><b>" + esc(p[0]) + "</b><u>" + p[1] + (p[1] === 1 ? " rank" : " ranks") + "</u><p>" + esc(p[2]) + "</p></div></div>";
        }).join("") + "</div>";
    }).join("");
    section("legacy", "The Legacy system", facts(lg.facts) + trees +
      '<p class="board-sub">' + esc(lg.treeNote) + "</p>");

    // Unseen spells
    var un = d.unseen;
    function sprows(list, withIcon) {
      return '<div class="spellrows">' + list.map(function (r) {
        return '<div class="sprow">' + img(withIcon ? (r[3] || "inv_misc_questionmark") : "inv_misc_questionmark") +
          '<b style="color:' + (CLASS_COLOUR[r[0]] || "#fff") + '">' + esc(r[1]) + '</b><span class="cls">' + esc(r[0]) +
          '</span><span class="why">' + esc(r[2]) + "</span></div>";
      }).join("") + "</div>";
    }
    section("unseen", "Spells the tooltips admit to", "<p class=\"board-sub\">" + esc(un.note) + "</p>" +
      "<h3>New to Forever</h3>" + sprows(un.new, true) +
      "<h3>Classic spells above the demo's level</h3>" + sprows(un.higher, false));

    // Class changes
    var cc = d.classChanges;
    var ccHtml = Object.keys(cc).map(function (k) {
      return "<details><summary style=\"color:" + (CLASS_COLOUR[k] || "#fff") + '">' + esc(k) + " (" + cc[k].length + " changes seen)</summary>" +
        cc[k].map(function (a) {
          return '<div class="abil">' + img(a[2] || "inv_misc_questionmark") + "<div><b>" + esc(a[0]) + "</b><p>" + esc(a[1]) + "</p></div></div>";
        }).join("") + "</details>";
    }).join("");
    section("classes", "Class changes, as seen in the demo", ccHtml);

    // World
    var w = d.world;
    function wtable(rows) {
      return '<table class="wtable">' + rows.map(function (r) {
        return "<tr><td>" + esc(r[0]) + "</td><td>" + esc(r[1] || "") + "</td></tr>";
      }).join("") + "</table>";
    }
    section("world", "The new world",
      "<h3>Zones</h3>" + wtable(w.zones) + "<h3>Dungeons</h3>" + wtable(w.dungeons) +
      "<h3>Raids</h3>" + wtable(w.raids) + "<h3>Battlegrounds</h3>" + wtable(w.battlegrounds));

    // Systems
    d.systems.forEach(function (sys, i) {
      section("sys" + i, sys.t, facts(sys.facts));
    });

    document.getElementById("cxnav").innerHTML = nav.join("");
    document.getElementById("cx").innerHTML = out.join("");
  }).catch(function (e) {
    document.getElementById("cx").innerHTML = "<p>The Codex failed to load. Refresh; the scribes are embarrassed.</p>";
  });
})();
