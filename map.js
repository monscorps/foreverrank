/* The Atlas v7: navigates like the game map on Blizzard's own painted art.
 * World, then continent, then zone. Left-click descends, right-click or Esc
 * climbs back out, X closes. Hotspots come straight from UiMapAssignment;
 * continent art is the classic client's until the Forever repaint exports. */
(function () {
  "use strict";
  var Z = [{"id":"16606","n":"Darkspear Islands","c":"New in Forever","sz":4,"new":1},{"id":"16591","n":"Riverglades","c":"New in Forever","sz":19,"new":1},{"id":"16651","n":"Shen'dralas","c":"New in Forever","sz":6,"new":1},{"id":"16593","n":"Zephras Isle","c":"New in Forever","sz":27,"new":1},{"id":"36","n":"Alterac Mountains","c":"Eastern Kingdoms","sz":21,"new":0},{"id":"45","n":"Arathi Highlands","c":"Eastern Kingdoms","sz":24,"new":0},{"id":"3","n":"Badlands","c":"Eastern Kingdoms","sz":17,"new":0},{"id":"4","n":"Blasted Lands","c":"Eastern Kingdoms","sz":9,"new":0},{"id":"46","n":"Burning Steppes","c":"Eastern Kingdoms","sz":13,"new":0},{"id":"41","n":"Deadwind Pass","c":"Eastern Kingdoms","sz":10,"new":0},{"id":"1","n":"Dun Morogh","c":"Eastern Kingdoms","sz":25,"new":0},{"id":"10","n":"Duskwood","c":"Eastern Kingdoms","sz":20,"new":0},{"id":"139","n":"Eastern Plaguelands","c":"Eastern Kingdoms","sz":34,"new":0},{"id":"12","n":"Elwynn Forest","c":"Eastern Kingdoms","sz":26,"new":0},{"id":"267","n":"Hillsbrad Foothills","c":"Eastern Kingdoms","sz":16,"new":0},{"id":"38","n":"Loch Modan","c":"Eastern Kingdoms","sz":16,"new":0},{"id":"44","n":"Redridge Mountains","c":"Eastern Kingdoms","sz":16,"new":0},{"id":"51","n":"Searing Gorge","c":"Eastern Kingdoms","sz":12,"new":0},{"id":"130","n":"Silverpine Forest","c":"Eastern Kingdoms","sz":24,"new":0},{"id":"33","n":"Stranglethorn Vale","c":"Eastern Kingdoms","sz":45,"new":0},{"id":"8","n":"Swamp of Sorrows","c":"Eastern Kingdoms","sz":15,"new":0},{"id":"47","n":"The Hinterlands","c":"Eastern Kingdoms","sz":22,"new":0},{"id":"85","n":"Tirisfal Glades","c":"Eastern Kingdoms","sz":30,"new":0},{"id":"28","n":"Western Plaguelands","c":"Eastern Kingdoms","sz":17,"new":0},{"id":"40","n":"Westfall","c":"Eastern Kingdoms","sz":19,"new":0},{"id":"11","n":"Wetlands","c":"Eastern Kingdoms","sz":28,"new":0},{"id":"331","n":"Ashenvale","c":"Kalimdor","sz":42,"new":0},{"id":"16","n":"Azshara","c":"Kalimdor","sz":31,"new":0},{"id":"148","n":"Darkshore","c":"Kalimdor","sz":17,"new":0},{"id":"405","n":"Desolace","c":"Kalimdor","sz":21,"new":0},{"id":"14","n":"Durotar","c":"Kalimdor","sz":28,"new":0},{"id":"15","n":"Dustwallow Marsh","c":"Kalimdor","sz":28,"new":0},{"id":"361","n":"Felwood","c":"Kalimdor","sz":18,"new":0},{"id":"357","n":"Feralas","c":"Kalimdor","sz":35,"new":0},{"id":"493","n":"Moonglade","c":"Kalimdor","sz":5,"new":0},{"id":"616","n":"Mount Hyjal","c":"Kalimdor","sz":9,"new":1},{"id":"215","n":"Mulgore","c":"Kalimdor","sz":29,"new":0},{"id":"1377","n":"Silithus","c":"Kalimdor","sz":21,"new":0},{"id":"406","n":"Stonetalon Mountains","c":"Kalimdor","sz":19,"new":0},{"id":"440","n":"Tanaris","c":"Kalimdor","sz":25,"new":0},{"id":"141","n":"Teldrassil","c":"Kalimdor","sz":24,"new":0},{"id":"17","n":"The Barrens","c":"Kalimdor","sz":44,"new":0},{"id":"400","n":"Thousand Needles","c":"Kalimdor","sz":22,"new":0},{"id":"490","n":"Un'Goro Crater","c":"Kalimdor","sz":12,"new":0},{"id":"618","n":"Winterspring","c":"Kalimdor","sz":18,"new":0},{"id":"1657","n":"Darnassus","c":"Cities","sz":5,"new":0},{"id":"1537","n":"Ironforge","c":"Cities","sz":0,"new":0},{"id":"1637","n":"Orgrimmar","c":"Cities","sz":0,"new":0},{"id":"1519","n":"Stormwind City","c":"Cities","sz":2,"new":0},{"id":"1638","n":"Thunder Bluff","c":"Cities","sz":4,"new":0},{"id":"1497","n":"Undercity","c":"Cities","sz":0,"new":0},{"id":"2597","n":"Alterac Valley","c":"Battlegrounds","sz":26,"new":0},{"id":"3358","n":"Arathi Basin","c":"Battlegrounds","sz":7,"new":0},{"id":"3277","n":"Warsong Gulch","c":"Battlegrounds","sz":2,"new":0}];
  var byId = {}; Z.forEach(function (z) { byId[z.id] = z; });
  // true geography: UiMapAssignment rectangles, normalized to the landmass crop
  var GEO = {"zones":{"ek":[{"a":"33","u":39.15,"v":79.41,"w":18.13,"h":18.13},{"a":"1","u":40.34,"v":48.34,"w":13.99,"h":13.99},{"a":"16591","u":50.83,"v":59.37,"w":13.78,"h":13.78},{"a":"85","u":36.84,"v":15.46,"w":12.84,"h":12.84},{"a":"28","u":44.27,"v":17.47,"w":12.22,"h":12.22},{"a":"139","u":51.86,"v":16.09,"w":12.22,"h":12.22},{"a":"130","u":35.65,"v":24.72,"w":11.93,"h":11.93},{"a":"11","u":46.56,"v":40.97,"w":11.75,"h":11.75},{"a":"47","u":49.93,"v":25.57,"w":10.94,"h":10.94},{"a":"45","u":47.92,"v":32.39,"w":10.23,"h":10.23},{"a":"40","u":36.88,"v":71.87,"w":9.94,"h":9.94},{"a":"12","u":41.09,"v":65.65,"w":9.86,"h":9.86},{"a":"4","u":48.98,"v":76.85,"w":9.52,"h":9.52},{"a":"267","u":42.42,"v":30.11,"w":9.09,"h":9.09},{"a":"46","u":46.21,"v":61.78,"w":8.32,"h":8.32},{"a":"36","u":43.23,"v":25.43,"w":7.95,"h":7.95},{"a":"38","u":51.12,"v":50.94,"w":7.84,"h":7.84},{"a":"10","u":43.09,"v":73.22,"w":7.67,"h":7.67},{"a":"41","u":47.82,"v":73.86,"w":7.1,"h":7.1},{"a":"3","u":51.36,"v":56.92,"w":7.07,"h":7.07},{"a":"8","u":51.77,"v":72.82,"w":6.52,"h":6.52},{"a":"51","u":46.37,"v":57.81,"w":6.34,"h":6.34},{"a":"44","u":50.23,"v":68.36,"w":6.17,"h":6.17},{"a":"1519","u":40.56,"v":65.89,"w":4.94,"h":4.94},{"a":"1497","u":42.97,"v":23.82,"w":2.73,"h":2.73},{"a":"1537","u":47.48,"v":51.29,"w":2.25,"h":2.25}],"kal":[{"a":"17","u":39.25,"v":45.6,"w":27.54,"h":27.54},{"a":"618","u":47.24,"v":17.39,"w":19.29,"h":19.29},{"a":"357","u":31.59,"v":61.82,"w":18.89,"h":18.89},{"a":"440","u":46.97,"v":76.12,"w":18.75,"h":18.75},{"a":"148","u":38.38,"v":18.21,"w":17.8,"h":17.8},{"a":"215","u":39.64,"v":51.09,"w":16.72,"h":16.72},{"a":"331","u":41.76,"v":33.13,"w":15.67,"h":15.67},{"a":"361","u":41.92,"v":23.1,"w":15.63,"h":15.63},{"a":"14","u":51.71,"v":44.8,"w":14.37,"h":14.37},{"a":"15","u":49.03,"v":60.46,"w":14.27,"h":14.27},{"a":"141","u":36.01,"v":3.95,"w":13.84,"h":13.83},{"a":"16","u":55.28,"v":30.4,"w":13.78,"h":13.78},{"a":"406","u":37.56,"v":40.29,"w":13.27,"h":13.27},{"a":"405","u":34.87,"v":50.33,"w":12.22,"h":12.22},{"a":"400","u":47.55,"v":68.34,"w":11.96,"h":11.96},{"a":"490","u":44.93,"v":76.49,"w":10.05,"h":10.05},{"a":"1377","u":39.48,"v":76.46,"w":9.47,"h":9.47},{"a":"616","u":48.88,"v":26.48,"w":9.44,"h":9.43},{"a":"493","u":50.13,"v":17.56,"w":6.27,"h":6.28},{"a":"16651","u":40.87,"v":59.92,"w":5.57,"h":5.57},{"a":"1637","u":56.38,"v":42.91,"w":3.81,"h":3.81},{"a":"1657","u":38.39,"v":10.44,"w":2.88,"h":2.88},{"a":"1638","u":44.97,"v":55.64,"w":2.84,"h":2.84}]}};
  var CONT = { ek: { name: "Eastern Kingdoms" }, kal: { name: "Kalimdor" } };
  var BGS = ["2597", "3277", "3358"];
  var NEWZ = ["16593", "16591", "16606", "16651"];
  var css = ".atlas-pill svg{margin-right:.35rem;vertical-align:-2px}" +
    ".atlas-btn:hover{border-color:#e5cc80}" +
    ".atlas{position:fixed;inset:0;z-index:950;background:rgba(5,9,18,.99);overflow:auto;padding:1.1rem;-webkit-overflow-scrolling:touch}" +
    ".atlas[hidden]{display:none}" +
    ".atlas-head{display:flex;align-items:center;gap:.6rem;max-width:1100px;margin:0 auto .8rem}" +
    ".atlas-crumb{display:flex;align-items:center;gap:.4rem;font:600 .8rem/1 var(--heading,inherit);color:#8b93a7}" +
    ".atlas-crumb button{font:inherit;color:#e5cc80;background:none;border:0;padding:0;cursor:pointer;letter-spacing:.04em}" +
    ".atlas-crumb b{color:#e8e2d0;letter-spacing:.04em}" +
    ".atlas-crumb i{font-style:normal;color:#3d4658}" +
    ".atlas-hint{margin-left:auto;color:#5c657a;font-size:.68rem}" +
    ".atlas-x{color:#8b93a7;background:none;border:1px solid rgba(139,147,167,.4);border-radius:2px;padding:.35rem .7rem;cursor:pointer;font-size:1rem}" +
    ".atlas-x:hover{color:#e5cc80;border-color:#e5cc80}" +
    ".atlas-az{position:relative;height:calc(100vh - 250px);min-height:380px;aspect-ratio:1.5;margin:0 auto;background:radial-gradient(ellipse at 50% 45%, rgba(16,28,50,.8), rgba(5,9,18,.2) 75%);border:1px solid rgba(139,147,167,.18);border-radius:2px}" +
".az-cont{position:absolute;background:none;border:0;padding:0;cursor:pointer}" +
".az-cont img{position:absolute;opacity:.62;filter:saturate(.8);transition:opacity .15s,filter .15s}" +
".az-cont:hover img{opacity:1;filter:none}" +
".az-cont b{position:absolute;left:50%;bottom:-1.6rem;transform:translateX(-50%);font:700 .8rem/1 var(--heading,inherit);letter-spacing:.12em;text-transform:uppercase;color:#8b93a7;transition:color .15s;white-space:nowrap}" +
".az-cont:hover b{color:#e5cc80;text-shadow:0 0 14px rgba(229,204,128,.4)}" +
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
    ".atlas-geo{position:relative;max-width:1002px;margin:0 auto;aspect-ratio:1.5;background:center / cover no-repeat #0b1322;border:1px solid rgba(139,147,167,.3);border-radius:2px}" +
".atlas-g{position:absolute;cursor:pointer;border:1px solid rgba(232,226,208,.0);border-radius:2px;background:none;padding:0;transition:border-color .12s,background .12s}" +
".atlas-g:hover{border-color:#e5cc80;background:rgba(229,204,128,.1);z-index:60!important;box-shadow:0 0 0 1px rgba(229,204,128,.35),0 4px 18px rgba(0,0,0,.35)}" +
".atlas-g b{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);padding:.25rem .45rem;font:700 .68rem/1.1 var(--heading,inherit);letter-spacing:.05em;color:#f4ead0;background:rgba(5,9,18,.85);border:1px solid rgba(229,204,128,.45);border-radius:2px;white-space:nowrap;opacity:0;transition:opacity .12s;pointer-events:none}" +
".atlas-g:hover b{opacity:1}" +
".atlas-g .nb{position:absolute;top:.2rem;left:.2rem;font:700 .5rem/1 var(--heading,inherit);color:#0d1626;background:#e5cc80;border-radius:2px;padding:.14rem .24rem}" +
".atlas-g.city{border:1px solid rgba(229,204,128,.75);background:rgba(229,204,128,.28);border-radius:50%;min-width:11px;min-height:11px}" +
".atlas-g.city:hover{background:#e5cc80}" +
".atlas-g.city b{left:110%;right:auto;bottom:-30%;background:rgba(5,9,18,.92);border:1px solid rgba(229,204,128,.4);border-radius:2px;padding:.2rem .35rem;white-space:nowrap;font-size:.58rem}" +
    ".atlas-view{max-width:1100px;margin:0 auto}" +
    ".atlas-view img{display:block;width:100%;max-width:1002px;margin:0 auto;border:1px solid rgba(139,147,167,.3);border-radius:2px}" +
    ".atlas-meta{max-width:1002px;margin:.6rem auto 0;color:#8b93a7;font-size:.8rem}";
  var st = document.createElement("style"); st.textContent = css; document.head.appendChild(st);
  var btn = document.createElement("a");
  btn.className = "pill atlas-pill"; btn.href = "#atlas";
  btn.innerHTML = '<svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" aria-hidden="true"><path d="M1 3.5 5.5 2l5 1.5L15 2v10.5L10.5 14l-5-1.5L1 14zM5.5 2v10.5M10.5 3.5V14"/></svg><span>Atlas</span>';
  btn.setAttribute("aria-label", "Open the world atlas");
  var topnav = document.querySelector("nav.top .top-nav");
  if (topnav) {
    var disc = topnav.querySelector(".discord");
    topnav.insertBefore(btn, disc || null);
  } else document.body.appendChild(btn);
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
      var zs = GEO.zones[view.cont] || [];
      var tiles2 = zs.map(function (g) {
        var z = byId[g.a];
        if (!z) return "";
        var city = {"1519":1,"1537":1,"1497":1,"1637":1,"1638":1,"1657":1}[g.a] === 1;
        return '<button type="button" class="atlas-g' + (city ? " city" : "") + '" data-z="' + z.id +
          '" style="left:' + g.u + '%;top:' + g.v + '%;width:' + g.w + '%;height:' + g.h + '%">' +
          (z["new"] && !city ? '<i class="nb">NEW</i>' : "") +
          "<b>" + esc(z.n) + "</b></button>";
      }).join("");
      ov.innerHTML = crumb() + '<div class="atlas-geo" style="background-image:url(/map/img/cont-' + view.cont + '.jpg)">' + tiles2 + "</div>" +
        '<p class="atlas-meta" style="max-width:1002px">Hover a region, click to open its map. Continent art is the classic client\u2019s; Forever\u2019s repainted version replaces it once exported.</p>';
    } else {
      // Azeroth: both continents in the ocean at their UiMapAssignment positions
      function contInner(key) {
        return '<img loading="lazy" src="/map/img/cont-' + key + '.jpg" alt="" style="inset:0;width:100%;height:100%;object-fit:cover;border-radius:2px">';
      }
      ov.innerHTML = crumb() +
        '<div class="atlas-az">' +
        '<button type="button" class="az-cont" data-cont="kal" style="left:3.99%;top:8.55%;width:36.84%;height:83.79%">' + contInner("kal") + "<b>Kalimdor</b></button>" +
        '<button type="button" class="az-cont" data-cont="ek" style="left:55.05%;top:9.94%;width:34.61%;height:76.97%">' + contInner("ek") + "<b>Eastern Kingdoms</b></button>" +
        "</div>" +
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
  btn.addEventListener("click", function (e) { e.preventDefault(); openAtlas(); });
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
