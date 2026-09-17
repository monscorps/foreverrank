/* The Atlas v3: navigates like the game map. World, then continent, then zone.
 * Left-click descends, right-click (or Esc) climbs back out, X closes.
 * Continents are zone mosaics in rough geography until the continent art and
 * UiMapAssignment hotspots are exported; the interaction model is final. */
(function () {
  "use strict";
  var Z = [{"id":"16606","n":"Darkspear Islands","c":"New in Forever","sz":4,"new":1},{"id":"16591","n":"Riverglades","c":"New in Forever","sz":19,"new":1},{"id":"16651","n":"Shen'dralas","c":"New in Forever","sz":6,"new":1},{"id":"16593","n":"Zephras Isle","c":"New in Forever","sz":27,"new":1},{"id":"36","n":"Alterac Mountains","c":"Eastern Kingdoms","sz":21,"new":0},{"id":"45","n":"Arathi Highlands","c":"Eastern Kingdoms","sz":24,"new":0},{"id":"3","n":"Badlands","c":"Eastern Kingdoms","sz":17,"new":0},{"id":"4","n":"Blasted Lands","c":"Eastern Kingdoms","sz":9,"new":0},{"id":"46","n":"Burning Steppes","c":"Eastern Kingdoms","sz":13,"new":0},{"id":"41","n":"Deadwind Pass","c":"Eastern Kingdoms","sz":10,"new":0},{"id":"1","n":"Dun Morogh","c":"Eastern Kingdoms","sz":25,"new":0},{"id":"10","n":"Duskwood","c":"Eastern Kingdoms","sz":20,"new":0},{"id":"139","n":"Eastern Plaguelands","c":"Eastern Kingdoms","sz":34,"new":0},{"id":"12","n":"Elwynn Forest","c":"Eastern Kingdoms","sz":26,"new":0},{"id":"267","n":"Hillsbrad Foothills","c":"Eastern Kingdoms","sz":16,"new":0},{"id":"38","n":"Loch Modan","c":"Eastern Kingdoms","sz":16,"new":0},{"id":"44","n":"Redridge Mountains","c":"Eastern Kingdoms","sz":16,"new":0},{"id":"51","n":"Searing Gorge","c":"Eastern Kingdoms","sz":12,"new":0},{"id":"130","n":"Silverpine Forest","c":"Eastern Kingdoms","sz":24,"new":0},{"id":"33","n":"Stranglethorn Vale","c":"Eastern Kingdoms","sz":45,"new":0},{"id":"8","n":"Swamp of Sorrows","c":"Eastern Kingdoms","sz":15,"new":0},{"id":"47","n":"The Hinterlands","c":"Eastern Kingdoms","sz":22,"new":0},{"id":"85","n":"Tirisfal Glades","c":"Eastern Kingdoms","sz":30,"new":0},{"id":"28","n":"Western Plaguelands","c":"Eastern Kingdoms","sz":17,"new":0},{"id":"40","n":"Westfall","c":"Eastern Kingdoms","sz":19,"new":0},{"id":"11","n":"Wetlands","c":"Eastern Kingdoms","sz":28,"new":0},{"id":"331","n":"Ashenvale","c":"Kalimdor","sz":42,"new":0},{"id":"16","n":"Azshara","c":"Kalimdor","sz":31,"new":0},{"id":"148","n":"Darkshore","c":"Kalimdor","sz":17,"new":0},{"id":"405","n":"Desolace","c":"Kalimdor","sz":21,"new":0},{"id":"14","n":"Durotar","c":"Kalimdor","sz":28,"new":0},{"id":"15","n":"Dustwallow Marsh","c":"Kalimdor","sz":28,"new":0},{"id":"361","n":"Felwood","c":"Kalimdor","sz":18,"new":0},{"id":"357","n":"Feralas","c":"Kalimdor","sz":35,"new":0},{"id":"493","n":"Moonglade","c":"Kalimdor","sz":5,"new":0},{"id":"616","n":"Mount Hyjal","c":"Kalimdor","sz":9,"new":1},{"id":"215","n":"Mulgore","c":"Kalimdor","sz":29,"new":0},{"id":"1377","n":"Silithus","c":"Kalimdor","sz":21,"new":0},{"id":"406","n":"Stonetalon Mountains","c":"Kalimdor","sz":19,"new":0},{"id":"440","n":"Tanaris","c":"Kalimdor","sz":25,"new":0},{"id":"141","n":"Teldrassil","c":"Kalimdor","sz":24,"new":0},{"id":"17","n":"The Barrens","c":"Kalimdor","sz":44,"new":0},{"id":"400","n":"Thousand Needles","c":"Kalimdor","sz":22,"new":0},{"id":"490","n":"Un'Goro Crater","c":"Kalimdor","sz":12,"new":0},{"id":"618","n":"Winterspring","c":"Kalimdor","sz":18,"new":0},{"id":"1657","n":"Darnassus","c":"Cities","sz":5,"new":0},{"id":"1537","n":"Ironforge","c":"Cities","sz":0,"new":0},{"id":"1637","n":"Orgrimmar","c":"Cities","sz":0,"new":0},{"id":"1519","n":"Stormwind City","c":"Cities","sz":2,"new":0},{"id":"1638","n":"Thunder Bluff","c":"Cities","sz":4,"new":0},{"id":"1497","n":"Undercity","c":"Cities","sz":0,"new":0},{"id":"2597","n":"Alterac Valley","c":"Battlegrounds","sz":26,"new":0},{"id":"3358","n":"Arathi Basin","c":"Battlegrounds","sz":7,"new":0},{"id":"3277","n":"Warsong Gulch","c":"Battlegrounds","sz":2,"new":0}];
  var byId = {}; Z.forEach(function (z) { byId[z.id] = z; });
  // rough geography: 4-column grids, north at the top
  var EK = [[0, 85, 28, 139], [130, 36, 0, 47], [0, 267, 45, 0], [0, 11, 38, 0], [0, 1, 3, 0],
            [0, 51, 46, 16591], [40, 12, 44, 0], [0, 10, 41, 8], [0, 33, 0, 4]];
  var KAL = [[141, 148, 493, 618], [0, 361, 616, 16], [0, 331, 0, 14], [406, 17, 0, 16606],
             [405, 215, 15, 0], [357, 16651, 400, 0], [0, 490, 440, 0], [0, 1377, 0, 16593]];
  var CONT = {
    ek: { name: "Eastern Kingdoms", grid: EK, cities: ["1519", "1537", "1497"] },
    kal: { name: "Kalimdor", grid: KAL, cities: ["1637", "1638", "1657"] }
  };
  var BGS = ["2597", "3277", "3358"];
  var NEWZ = ["16593", "16591", "16606", "16651"];
  var css = ".atlas-btn{position:fixed;right:18px;bottom:18px;z-index:900;display:flex;align-items:center;gap:.45rem;font:700 .78rem/1 var(--heading,inherit);letter-spacing:.1em;text-transform:uppercase;color:#e5cc80;background:rgba(13,22,38,.94);border:1px solid rgba(229,204,128,.65);border-radius:2px;padding:.7rem .95rem;cursor:pointer;box-shadow:0 2px 14px rgba(0,0,0,.5)}" +
    ".atlas-btn:hover{border-color:#e5cc80}" +
    ".atlas{position:fixed;inset:0;z-index:950;background:rgba(5,9,18,.97);overflow:auto;padding:1.1rem;-webkit-overflow-scrolling:touch}" +
    ".atlas[hidden]{display:none}" +
    ".atlas-head{display:flex;align-items:center;gap:.6rem;max-width:1100px;margin:0 auto .8rem}" +
    ".atlas-crumb{display:flex;align-items:center;gap:.4rem;font:600 .8rem/1 var(--heading,inherit);color:#8b93a7}" +
    ".atlas-crumb button{font:inherit;color:#e5cc80;background:none;border:0;padding:0;cursor:pointer;letter-spacing:.04em}" +
    ".atlas-crumb b{color:#e8e2d0;letter-spacing:.04em}" +
    ".atlas-crumb i{font-style:normal;color:#3d4658}" +
    ".atlas-hint{margin-left:auto;color:#5c657a;font-size:.68rem}" +
    ".atlas-x{color:#8b93a7;background:none;border:1px solid rgba(139,147,167,.4);border-radius:2px;padding:.35rem .7rem;cursor:pointer;font-size:1rem}" +
    ".atlas-x:hover{color:#e5cc80;border-color:#e5cc80}" +
    ".atlas-world{display:grid;grid-template-columns:1fr 1fr;gap:.8rem;max-width:1100px;margin:0 auto}" +
    ".atlas-cont{position:relative;cursor:pointer;border:1px solid rgba(139,147,167,.3);border-radius:2px;overflow:hidden;background:#0d1626;padding:0;min-height:230px}" +
    ".atlas-cont:hover{border-color:#e5cc80}" +
    ".atlas-cont .mosaic{display:grid;grid-template-columns:1fr 1fr;height:230px;filter:saturate(.85) brightness(.8)}" +
    ".atlas-cont:hover .mosaic{filter:none}" +
    ".atlas-cont .mosaic img{width:100%;height:115px;object-fit:cover;display:block}" +
    ".atlas-cont b{position:absolute;left:0;right:0;bottom:0;padding:.7rem .8rem;font:700 .95rem/1 var(--heading,inherit);letter-spacing:.08em;text-transform:uppercase;color:#e8e2d0;background:linear-gradient(transparent,rgba(5,9,18,.95))}" +
    ".atlas-row{max-width:1100px;margin:.9rem auto 0}" +
    ".atlas-row h4{font:600 .7rem/1 var(--heading,inherit);letter-spacing:.1em;text-transform:uppercase;color:#8b93a7;margin:0 0 .45rem}" +
    ".atlas-tiles{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:.5rem}" +
    ".atlas-t{position:relative;cursor:pointer;border:1px solid rgba(139,147,167,.25);border-radius:2px;overflow:hidden;background:#0d1626;padding:0}" +
    ".atlas-t img{display:block;width:100%;height:86px;object-fit:cover;opacity:.85;transition:transform .15s,opacity .15s}" +
    ".atlas-t:hover{border-color:#e5cc80;z-index:2}.atlas-t:hover img{opacity:1;transform:scale(1.06)}" +
    ".atlas-t b{position:absolute;left:0;right:0;bottom:0;padding:.35rem .45rem;font:600 .64rem/1.15 var(--heading,inherit);color:#e8e2d0;background:linear-gradient(transparent,rgba(5,9,18,.94))}" +
    ".atlas-t .nb{position:absolute;top:.3rem;left:.3rem;font:700 .55rem/1 var(--heading,inherit);letter-spacing:.05em;color:#0d1626;background:#e5cc80;border-radius:2px;padding:.18rem .3rem}" +
    ".atlas-cgrid{display:grid;grid-template-columns:repeat(4,1fr);gap:.45rem;max-width:1100px;margin:0 auto}" +
    ".atlas-cgrid .blank{border:0;background:none}" +
    ".atlas-view{max-width:1100px;margin:0 auto}" +
    ".atlas-view img{display:block;width:100%;max-width:1002px;margin:0 auto;border:1px solid rgba(139,147,167,.3);border-radius:2px}" +
    ".atlas-meta{max-width:1002px;margin:.6rem auto 0;color:#8b93a7;font-size:.8rem}";
  var st = document.createElement("style"); st.textContent = css; document.head.appendChild(st);
  var btn = document.createElement("button"); btn.type = "button"; btn.className = "atlas-btn";
  btn.innerHTML = '<svg width="15" height="15" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" aria-hidden="true"><path d="M1 3.5 5.5 2l5 1.5L15 2v10.5L10.5 14l-5-1.5L1 14zM5.5 2v10.5M10.5 3.5V14"/></svg><span>Atlas</span>';
  btn.setAttribute("aria-label", "Open the zone atlas");
  document.body.appendChild(btn);
  var ov = document.createElement("div"); ov.className = "atlas"; ov.hidden = true; document.body.appendChild(ov);
  var view = { lvl: "world", cont: null, zone: null };
  function esc(s) { return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;"); }
  function tile(z, extra) {
    return '<button type="button" class="atlas-t" data-z="' + z.id + '">' +
      '<img loading="lazy" src="/map/img/' + z.id + '.jpg" alt="">' +
      (z["new"] ? '<i class="nb">NEW</i>' : "") + "<b>" + esc(z.n) + (extra ? " " + extra : "") + "</b></button>";
  }
  function crumb() {
    var parts = ['<button type="button" data-lvl="world">Azeroth</button>'];
    if (view.lvl !== "world" && view.cont) parts.push("<i>/</i>" + (view.lvl === "cont" ? "<b>" + CONT[view.cont].name + "</b>" : '<button type="button" data-lvl="cont">' + CONT[view.cont].name + "</button>"));
    if (view.lvl === "zone") parts.push("<i>/</i><b>" + esc(view.zone.n) + "</b>");
    return '<div class="atlas-head"><div class="atlas-crumb">' + parts.join("") + "</div>" +
      '<span class="atlas-hint">Left-click to enter, right-click to step out</span>' +
      '<button type="button" class="atlas-x" aria-label="Close">×</button></div>';
  }
  function draw() {
    if (view.lvl === "zone") {
      var z = view.zone;
      ov.innerHTML = crumb() + '<div class="atlas-view"><img src="/map/img/' + z.id + '.jpg" alt="' + esc(z.n) + ' map">' +
        '<p class="atlas-meta"><b style="color:#e8e2d0">' + esc(z.n) + "</b> · " + esc(z.c) +
        (z.sz ? " · " + z.sz + " named subzones in the client" : "") + ". More lands here as the beta gives it up.</p></div>";
    } else if (view.lvl === "cont") {
      var c = CONT[view.cont];
      var cells = c.grid.map(function (row) {
        return row.map(function (id) {
          var z = byId[String(id)];
          return z ? tile(z) : '<span class="blank"></span>';
        }).join("");
      }).join("");
      var cities = c.cities.map(function (id) { return byId[id] ? tile(byId[id]) : ""; }).join("");
      ov.innerHTML = crumb() + '<div class="atlas-cgrid">' + cells + "</div>" +
        '<div class="atlas-row"><h4>Cities</h4><div class="atlas-tiles">' + cities + "</div></div>";
    } else {
      function mosaic(ids) { return '<span class="mosaic">' + ids.map(function (id) { return '<img loading="lazy" src="/map/img/' + id + '.jpg" alt="">'; }).join("") + "</span>"; }
      ov.innerHTML = crumb() +
        '<div class="atlas-world">' +
        '<button type="button" class="atlas-cont" data-cont="ek">' + mosaic(["85", "12", "33", "139"]) + "<b>Eastern Kingdoms</b></button>" +
        '<button type="button" class="atlas-cont" data-cont="kal">' + mosaic(["141", "17", "440", "616"]) + "<b>Kalimdor</b></button></div>" +
        '<div class="atlas-row"><h4>New in Forever</h4><div class="atlas-tiles">' + NEWZ.map(function (id) { return tile(byId[id]); }).join("") + "</div></div>" +
        '<div class="atlas-row"><h4>Battlegrounds</h4><div class="atlas-tiles">' + BGS.map(function (id) { return tile(byId[id]); }).join("") + "</div></div>";
    }
    ov.scrollTop = 0;
  }
  function close() { ov.hidden = true; document.body.style.overflow = ""; if (location.hash === "#atlas") { try { history.replaceState(null, "", location.pathname + location.search); } catch (e) {} } }
  function up() {
    if (view.lvl === "zone") { view.lvl = view.cont ? "cont" : "world"; view.zone = null; draw(); }
    else if (view.lvl === "cont") { view.lvl = "world"; view.cont = null; draw(); }
    else close();
  }
  function openAtlas() { view = { lvl: "world", cont: null, zone: null }; draw(); ov.hidden = false; document.body.style.overflow = "hidden"; }
  btn.addEventListener("click", openAtlas);
  if (location.hash === "#atlas") openAtlas();
  window.addEventListener("hashchange", function () { if (location.hash === "#atlas") openAtlas(); });
  ov.addEventListener("contextmenu", function (e) { e.preventDefault(); up(); });
  ov.addEventListener("click", function (e) {
    var t = e.target.closest && e.target.closest("button");
    if (!t) return;
    if (t.className === "atlas-x") { close(); return; }
    if (t.hasAttribute("data-lvl")) {
      var l = t.getAttribute("data-lvl");
      if (l === "world") { view = { lvl: "world", cont: null, zone: null }; }
      else { view.lvl = "cont"; view.zone = null; }
      draw(); return;
    }
    if (t.hasAttribute("data-cont")) { view.lvl = "cont"; view.cont = t.getAttribute("data-cont"); draw(); return; }
    if (t.hasAttribute("data-z")) {
      var z = byId[t.getAttribute("data-z")];
      if (!z) return;
      if (!view.cont) view.cont = z.c === "Eastern Kingdoms" ? "ek" : z.c === "Kalimdor" ? "kal" : view.cont;
      view.lvl = "zone"; view.zone = z; draw();
    }
  });
  document.addEventListener("keydown", function (e) { if (e.key === "Escape" && !ov.hidden) up(); });
})();
