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

    // Legacy: not a list, a CALCULATOR. 16 points, spend them, share the link.
    var lg = d.legacy;
    var BUDGET = 16;
    var LG = lg.trees.map(function (t) { return (t.perks || []).map(function () { return 0; }); });
    (function () {
      var p = new URLSearchParams(location.search).get("lg");
      if (!p) return;
      p.split("-").forEach(function (seg, ti) {
        for (var i = 0; i < seg.length; i++) if (LG[ti]) LG[ti][i] = +seg[i] || 0;
      });
    })();
    function lgSpent() { return LG.reduce(function (a, t) { return a + t.reduce(function (x, y) { return x + y; }, 0); }, 0); }
    function lgURL() {
      var code = LG.map(function (t) { return t.join(""); }).join("-");
      history.replaceState(null, "", lgSpent() ? "?lg=" + code + "#legacy" : location.pathname + "#legacy");
    }
    function legacyHTML() {
      var left = BUDGET - lgSpent();
      return '<div class="talenthead"><h3>Spend your 16</h3><span class="pts' + (left === 0 ? " alldone" : "") + '">' +
        (left === 0 ? "All 16 placed" : left + " points left") + "</span>" +
        '<button type="button" class="share" id="lg-share">Share legacy build</button>' +
        '<button type="button" class="share" id="lg-reset">Reset</button></div>' +
        '<div class="lgtrees">' +
        lg.trees.map(function (t, ti) {
          var pts = LG[ti].reduce(function (a, b) { return a + b; }, 0);
          var slots = (t.perks || []).map(function (p, i) {
            var r = LG[ti][i] || 0;
            return '<div class="lslot' + (r >= p[1] ? " maxed" : r > 0 ? " part" : "") + '" data-lg="' + ti + ":" + i + '" ' +
              'data-tip="' + esc(p[0]) + "|Rank " + r + "/" + p[1] + "|" + esc(p[2]) + '">' +
              img(p[3] || "inv_misc_questionmark") + '<span class="l-rank">' + r + "/" + p[1] + "</span></div>";
          }).join("");
          if (t.name === "Professions")
            slots += '<div class="lslot locked" data-tip="Placeholder||To be added in future patch content."></div>' +
                     '<div class="lslot locked" data-tip="Placeholder||To be added in future patch content."></div>';
          return '<div class="lgtree"><div class="lg-head">' + img(t.icon) + "<b>" + esc(t.name) +
            '</b><u>' + pts + "</u></div><div class=\"lg-grid\">" + slots + "</div></div>";
        }).join("") + "</div>" +
        '<p class="board-sub">Left click adds a point, right click removes. Hover a perk for the tooltip. ' + esc(lg.treeNote) +
        " In game the trees are tiered like talent trees, with some perks locked behind earlier choices; the demo footage never showed which perk sits in which tier, so this calculator leaves every perk open until the beta client settles the layout.</p>";
    }
    var lgTip = null;
    function lgTipShow(slot, x, y) {
      var parts = (slot.getAttribute("data-tip") || "").split("|");
      if (!lgTip) { lgTip = document.createElement("div"); lgTip.className = "tip"; document.body.appendChild(lgTip); }
      lgTip.innerHTML = "<b>" + parts[0] + "</b>" + (parts[1] ? '<u>' + parts[1] + "</u>" : "") + "<p>" + (parts[2] || "") + "</p>";
      lgTip.style.display = "block";
      var w = lgTip.offsetWidth, h = lgTip.offsetHeight;
      lgTip.style.left = Math.min(x + 14, window.innerWidth - w - 8) + "px";
      lgTip.style.top = Math.max(8, Math.min(y + 14, window.innerHeight - h - 8)) + "px";
    }
    function lgTipHide() { if (lgTip) lgTip.style.display = "none"; }
    function drawLegacy() {
      var el = document.getElementById("legacy");
      lgTipHide();
      el.innerHTML = "<h2>The Legacy system</h2>" + facts(lg.facts) + legacyHTML();
      lgURL();
      el.querySelectorAll(".lslot").forEach(function (s) {
        s.addEventListener("mousemove", function (e) { lgTipShow(s, e.clientX, e.clientY); });
        s.addEventListener("mouseleave", lgTipHide);
      });
      el.querySelectorAll(".lslot:not(.locked)").forEach(function (card) {
        var pr = card.getAttribute("data-lg").split(":"), ti = +pr[0], i = +pr[1];
        card.addEventListener("click", function () {
          if (lgSpent() >= BUDGET) return;
          LG[ti][i] = Math.min(lg.trees[ti].perks[i][1], (LG[ti][i] || 0) + 1);
          drawLegacy();
        });
        card.addEventListener("contextmenu", function (e) {
          e.preventDefault();
          if ((LG[ti][i] || 0) > 0) { LG[ti][i]--; drawLegacy(); }
        });
      });
      var sh = document.getElementById("lg-share");
      if (sh) sh.addEventListener("click", function () {
        var url = location.href;
        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(url).then(function () {
            sh.textContent = "Link copied"; setTimeout(function () { sh.textContent = "Share legacy build"; }, 1600);
          });
        } else prompt("Copy this:", url);
      });
      var rs = document.getElementById("lg-reset");
      if (rs) rs.addEventListener("click", function () {
        LG = lg.trees.map(function (t) { return (t.perks || []).map(function () { return 0; }); });
        drawLegacy();
      });
    }
    section("legacy", "The Legacy system", "");

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
      "<h3>Genuinely new spells</h3>" + sprows(un.new, true) +
      "<h3>Granted by talents (already in the trees)</h3>" + sprows(un.granted || [], true) +
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
      (w.facts ? facts(w.facts) : "") +
      "<h3>Zones</h3>" + wtable(w.zones) + "<h3>Dungeons</h3>" + wtable(w.dungeons) +
      "<h3>Raids</h3>" + wtable(w.raids) + "<h3>Battlegrounds</h3>" + wtable(w.battlegrounds));

    // Systems
    d.systems.forEach(function (sys, i) {
      section("sys" + i, sys.t, facts(sys.facts));
    });

    document.getElementById("cxnav").innerHTML = nav.join("");
    document.getElementById("cx").innerHTML = out.join("");
    drawLegacy();
    // Scrollspy: the nav knows where you are.
    var links = document.querySelectorAll(".cxnav a");
    var obs = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (!en.isIntersecting) return;
        links.forEach(function (a) { a.classList.toggle("on", a.getAttribute("href") === "#" + en.target.id); });
      });
    }, { rootMargin: "-20% 0px -70% 0px" });
    document.querySelectorAll(".cx section").forEach(function (sec) { obs.observe(sec); });
  }).catch(function (e) {
    document.getElementById("cx").innerHTML = "<p>The Codex failed to load. Refresh; the scribes are embarrassed.</p>";
  });
})();
