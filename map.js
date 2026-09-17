/* The Atlas v7: navigates like the game map on Blizzard's own painted art.
 * World, then continent, then zone. Left-click descends, right-click or Esc
 * climbs back out, X closes. Hotspots come straight from UiMapAssignment;
 * continent art is the classic client's until the Forever repaint exports. */
(function () {
  "use strict";
  var Z = [{"id":"16606","n":"Darkspear Islands","c":"New in Forever","sz":4,"new":1},{"id":"16591","n":"Riverglades","c":"New in Forever","sz":19,"new":1},{"id":"16651","n":"Shen'dralas","c":"New in Forever","sz":6,"new":1},{"id":"16593","n":"Zephras Isle","c":"New in Forever","sz":27,"new":1},{"id":"36","n":"Alterac Mountains","c":"Eastern Kingdoms","sz":21,"new":0},{"id":"45","n":"Arathi Highlands","c":"Eastern Kingdoms","sz":24,"new":0},{"id":"3","n":"Badlands","c":"Eastern Kingdoms","sz":17,"new":0},{"id":"4","n":"Blasted Lands","c":"Eastern Kingdoms","sz":9,"new":0},{"id":"46","n":"Burning Steppes","c":"Eastern Kingdoms","sz":13,"new":0},{"id":"41","n":"Deadwind Pass","c":"Eastern Kingdoms","sz":10,"new":0},{"id":"1","n":"Dun Morogh","c":"Eastern Kingdoms","sz":25,"new":0},{"id":"10","n":"Duskwood","c":"Eastern Kingdoms","sz":20,"new":0},{"id":"139","n":"Eastern Plaguelands","c":"Eastern Kingdoms","sz":34,"new":0},{"id":"12","n":"Elwynn Forest","c":"Eastern Kingdoms","sz":26,"new":0},{"id":"267","n":"Hillsbrad Foothills","c":"Eastern Kingdoms","sz":16,"new":0},{"id":"38","n":"Loch Modan","c":"Eastern Kingdoms","sz":16,"new":0},{"id":"44","n":"Redridge Mountains","c":"Eastern Kingdoms","sz":16,"new":0},{"id":"51","n":"Searing Gorge","c":"Eastern Kingdoms","sz":12,"new":0},{"id":"130","n":"Silverpine Forest","c":"Eastern Kingdoms","sz":24,"new":0},{"id":"33","n":"Stranglethorn Vale","c":"Eastern Kingdoms","sz":45,"new":0},{"id":"8","n":"Swamp of Sorrows","c":"Eastern Kingdoms","sz":15,"new":0},{"id":"47","n":"The Hinterlands","c":"Eastern Kingdoms","sz":22,"new":0},{"id":"85","n":"Tirisfal Glades","c":"Eastern Kingdoms","sz":30,"new":0},{"id":"28","n":"Western Plaguelands","c":"Eastern Kingdoms","sz":17,"new":0},{"id":"40","n":"Westfall","c":"Eastern Kingdoms","sz":19,"new":0},{"id":"11","n":"Wetlands","c":"Eastern Kingdoms","sz":28,"new":0},{"id":"331","n":"Ashenvale","c":"Kalimdor","sz":42,"new":0},{"id":"16","n":"Azshara","c":"Kalimdor","sz":31,"new":0},{"id":"148","n":"Darkshore","c":"Kalimdor","sz":17,"new":0},{"id":"405","n":"Desolace","c":"Kalimdor","sz":21,"new":0},{"id":"14","n":"Durotar","c":"Kalimdor","sz":28,"new":0},{"id":"15","n":"Dustwallow Marsh","c":"Kalimdor","sz":28,"new":0},{"id":"361","n":"Felwood","c":"Kalimdor","sz":18,"new":0},{"id":"357","n":"Feralas","c":"Kalimdor","sz":35,"new":0},{"id":"493","n":"Moonglade","c":"Kalimdor","sz":5,"new":0},{"id":"616","n":"Mount Hyjal","c":"Kalimdor","sz":9,"new":1},{"id":"215","n":"Mulgore","c":"Kalimdor","sz":29,"new":0},{"id":"1377","n":"Silithus","c":"Kalimdor","sz":21,"new":0},{"id":"406","n":"Stonetalon Mountains","c":"Kalimdor","sz":19,"new":0},{"id":"440","n":"Tanaris","c":"Kalimdor","sz":25,"new":0},{"id":"141","n":"Teldrassil","c":"Kalimdor","sz":24,"new":0},{"id":"17","n":"The Barrens","c":"Kalimdor","sz":44,"new":0},{"id":"400","n":"Thousand Needles","c":"Kalimdor","sz":22,"new":0},{"id":"490","n":"Un'Goro Crater","c":"Kalimdor","sz":12,"new":0},{"id":"618","n":"Winterspring","c":"Kalimdor","sz":18,"new":0},{"id":"1657","n":"Darnassus","c":"Cities","sz":5,"new":0},{"id":"1537","n":"Ironforge","c":"Cities","sz":0,"new":0},{"id":"1637","n":"Orgrimmar","c":"Cities","sz":0,"new":0},{"id":"1519","n":"Stormwind City","c":"Cities","sz":2,"new":0},{"id":"1638","n":"Thunder Bluff","c":"Cities","sz":4,"new":0},{"id":"1497","n":"Undercity","c":"Cities","sz":0,"new":0},{"id":"2597","n":"Alterac Valley","c":"Battlegrounds","sz":26,"new":0},{"id":"3358","n":"Arathi Basin","c":"Battlegrounds","sz":7,"new":0},{"id":"3277","n":"Warsong Gulch","c":"Battlegrounds","sz":2,"new":0}];
  var byId = {}; Z.forEach(function (z) { byId[z.id] = z; });
  // true geography: UiMapAssignment rectangles, normalized to the landmass crop
  var GEO = {"zones":{"kal":[{"a":"17","u":23.55,"v":46.0,"w":65.78,"h":28.89},{"a":"618","u":42.63,"v":16.41,"w":46.07,"h":20.24},{"a":"357","u":5.25,"v":63.02,"w":45.12,"h":19.82},{"a":"440","u":41.99,"v":78.02,"w":44.78,"h":19.67},{"a":"148","u":21.47,"v":17.27,"w":42.51,"h":18.67},{"a":"215","u":24.48,"v":51.76,"w":39.93,"h":17.54},{"a":"331","u":29.54,"v":32.92,"w":37.43,"h":16.44},{"a":"361","u":29.93,"v":22.4,"w":37.33,"h":16.4},{"a":"14","u":53.31,"v":45.16,"w":34.32,"h":15.08},{"a":"15","u":46.91,"v":61.59,"w":34.08,"h":14.97},{"a":"141","u":15.81,"v":2.31,"w":33.05,"h":14.51},{"a":"16","u":61.83,"v":30.06,"w":32.91,"h":14.46},{"a":"406","u":19.51,"v":40.43,"w":31.69,"h":13.92},{"a":"405","u":13.09,"v":50.97,"w":29.19,"h":12.82},{"a":"400","u":43.37,"v":69.86,"w":28.56,"h":12.55},{"a":"490","u":37.11,"v":78.41,"w":24.0,"h":10.54},{"a":"1377","u":24.1,"v":78.38,"w":22.62,"h":9.93},{"a":"616","u":46.55,"v":25.94,"w":22.55,"h":9.89},{"a":"493","u":49.53,"v":16.59,"w":14.97,"h":6.59},{"a":"16651","u":27.42,"v":61.03,"w":13.3,"h":5.84},{"a":"1637","u":64.46,"v":43.18,"w":9.1,"h":4.0},{"a":"1657","u":21.5,"v":9.12,"w":6.88,"h":3.02},{"a":"1638","u":37.21,"v":56.54,"w":6.78,"h":2.98}],"ek":[{"a":"33","u":17.09,"v":76.49,"w":54.35,"h":20.96},{"a":"1","u":20.65,"v":40.56,"w":41.94,"h":16.18},{"a":"16591","u":52.1,"v":53.32,"w":41.31,"h":15.93},{"a":"85","u":10.16,"v":2.54,"w":38.49,"h":14.85},{"a":"28","u":32.43,"v":4.87,"w":36.63,"h":14.13},{"a":"139","u":55.19,"v":3.27,"w":36.63,"h":14.13},{"a":"130","u":6.59,"v":13.25,"w":35.76,"h":13.8},{"a":"11","u":39.3,"v":32.04,"w":35.22,"h":13.59},{"a":"47","u":49.4,"v":14.23,"w":32.79,"h":12.65},{"a":"45","u":43.38,"v":22.12,"w":30.67,"h":11.83},{"a":"40","u":10.28,"v":67.77,"w":29.8,"h":11.49},{"a":"12","u":22.9,"v":60.58,"w":29.56,"h":11.4},{"a":"4","u":46.55,"v":73.53,"w":28.54,"h":11.01},{"a":"267","u":26.89,"v":19.48,"w":27.25,"h":10.51},{"a":"46","u":38.25,"v":56.11,"w":24.94,"h":9.62},{"a":"36","u":29.32,"v":14.07,"w":23.83,"h":9.19},{"a":"38","u":52.97,"v":43.57,"w":23.5,"h":9.07},{"a":"10","u":28.9,"v":69.33,"w":22.99,"h":8.87},{"a":"41","u":43.08,"v":70.07,"w":21.28,"h":8.21},{"a":"3","u":53.69,"v":50.49,"w":21.19,"h":8.18},{"a":"8","u":54.92,"v":68.87,"w":19.54,"h":7.54},{"a":"51","u":38.73,"v":51.51,"w":19.0,"h":7.33},{"a":"44","u":50.3,"v":63.71,"w":18.5,"h":7.13},{"a":"1519","u":21.31,"v":60.86,"w":14.81,"h":5.71},{"a":"1497","u":28.54,"v":12.21,"w":8.18,"h":3.16},{"a":"1537","u":42.06,"v":43.98,"w":6.74,"h":2.6}]},"aspect":{"kal":0.6593,"ek":0.5786}};
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
    ".atlas-geo{position:relative;height:calc(100vh - 170px);min-height:420px;max-width:100%;margin:0 auto;background:#0b1322 center / 100% 100% no-repeat;border:1px solid rgba(139,147,167,.3);border-radius:2px}" +
"@media (max-width:820px){.atlas-geo{height:auto;width:100%}}" +
".atlas-g{position:absolute;cursor:pointer;border:1px solid rgba(232,226,208,.16);border-radius:2px;background:none;padding:0;transition:border-color .12s,background .12s}" +
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
      ov.innerHTML = crumb() + '<div class="atlas-geo" style="aspect-ratio:' + GEO.aspect[view.cont] + ';background-image:url(/map/img/cont-' + view.cont + '.jpg)">' + tiles2 + "</div>" +
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
