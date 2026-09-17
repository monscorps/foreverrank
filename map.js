/* The Atlas v3: navigates like the game map. World, then continent, then zone.
 * Left-click descends, right-click (or Esc) climbs back out, X closes.
 * Continents are zone mosaics in rough geography until the continent art and
 * UiMapAssignment hotspots are exported; the interaction model is final. */
(function () {
  "use strict";
  var Z = [{"id":"16606","n":"Darkspear Islands","c":"New in Forever","sz":4,"new":1},{"id":"16591","n":"Riverglades","c":"New in Forever","sz":19,"new":1},{"id":"16651","n":"Shen'dralas","c":"New in Forever","sz":6,"new":1},{"id":"16593","n":"Zephras Isle","c":"New in Forever","sz":27,"new":1},{"id":"36","n":"Alterac Mountains","c":"Eastern Kingdoms","sz":21,"new":0},{"id":"45","n":"Arathi Highlands","c":"Eastern Kingdoms","sz":24,"new":0},{"id":"3","n":"Badlands","c":"Eastern Kingdoms","sz":17,"new":0},{"id":"4","n":"Blasted Lands","c":"Eastern Kingdoms","sz":9,"new":0},{"id":"46","n":"Burning Steppes","c":"Eastern Kingdoms","sz":13,"new":0},{"id":"41","n":"Deadwind Pass","c":"Eastern Kingdoms","sz":10,"new":0},{"id":"1","n":"Dun Morogh","c":"Eastern Kingdoms","sz":25,"new":0},{"id":"10","n":"Duskwood","c":"Eastern Kingdoms","sz":20,"new":0},{"id":"139","n":"Eastern Plaguelands","c":"Eastern Kingdoms","sz":34,"new":0},{"id":"12","n":"Elwynn Forest","c":"Eastern Kingdoms","sz":26,"new":0},{"id":"267","n":"Hillsbrad Foothills","c":"Eastern Kingdoms","sz":16,"new":0},{"id":"38","n":"Loch Modan","c":"Eastern Kingdoms","sz":16,"new":0},{"id":"44","n":"Redridge Mountains","c":"Eastern Kingdoms","sz":16,"new":0},{"id":"51","n":"Searing Gorge","c":"Eastern Kingdoms","sz":12,"new":0},{"id":"130","n":"Silverpine Forest","c":"Eastern Kingdoms","sz":24,"new":0},{"id":"33","n":"Stranglethorn Vale","c":"Eastern Kingdoms","sz":45,"new":0},{"id":"8","n":"Swamp of Sorrows","c":"Eastern Kingdoms","sz":15,"new":0},{"id":"47","n":"The Hinterlands","c":"Eastern Kingdoms","sz":22,"new":0},{"id":"85","n":"Tirisfal Glades","c":"Eastern Kingdoms","sz":30,"new":0},{"id":"28","n":"Western Plaguelands","c":"Eastern Kingdoms","sz":17,"new":0},{"id":"40","n":"Westfall","c":"Eastern Kingdoms","sz":19,"new":0},{"id":"11","n":"Wetlands","c":"Eastern Kingdoms","sz":28,"new":0},{"id":"331","n":"Ashenvale","c":"Kalimdor","sz":42,"new":0},{"id":"16","n":"Azshara","c":"Kalimdor","sz":31,"new":0},{"id":"148","n":"Darkshore","c":"Kalimdor","sz":17,"new":0},{"id":"405","n":"Desolace","c":"Kalimdor","sz":21,"new":0},{"id":"14","n":"Durotar","c":"Kalimdor","sz":28,"new":0},{"id":"15","n":"Dustwallow Marsh","c":"Kalimdor","sz":28,"new":0},{"id":"361","n":"Felwood","c":"Kalimdor","sz":18,"new":0},{"id":"357","n":"Feralas","c":"Kalimdor","sz":35,"new":0},{"id":"493","n":"Moonglade","c":"Kalimdor","sz":5,"new":0},{"id":"616","n":"Mount Hyjal","c":"Kalimdor","sz":9,"new":1},{"id":"215","n":"Mulgore","c":"Kalimdor","sz":29,"new":0},{"id":"1377","n":"Silithus","c":"Kalimdor","sz":21,"new":0},{"id":"406","n":"Stonetalon Mountains","c":"Kalimdor","sz":19,"new":0},{"id":"440","n":"Tanaris","c":"Kalimdor","sz":25,"new":0},{"id":"141","n":"Teldrassil","c":"Kalimdor","sz":24,"new":0},{"id":"17","n":"The Barrens","c":"Kalimdor","sz":44,"new":0},{"id":"400","n":"Thousand Needles","c":"Kalimdor","sz":22,"new":0},{"id":"490","n":"Un'Goro Crater","c":"Kalimdor","sz":12,"new":0},{"id":"618","n":"Winterspring","c":"Kalimdor","sz":18,"new":0},{"id":"1657","n":"Darnassus","c":"Cities","sz":5,"new":0},{"id":"1537","n":"Ironforge","c":"Cities","sz":0,"new":0},{"id":"1637","n":"Orgrimmar","c":"Cities","sz":0,"new":0},{"id":"1519","n":"Stormwind City","c":"Cities","sz":2,"new":0},{"id":"1638","n":"Thunder Bluff","c":"Cities","sz":4,"new":0},{"id":"1497","n":"Undercity","c":"Cities","sz":0,"new":0},{"id":"2597","n":"Alterac Valley","c":"Battlegrounds","sz":26,"new":0},{"id":"3358","n":"Arathi Basin","c":"Battlegrounds","sz":7,"new":0},{"id":"3277","n":"Warsong Gulch","c":"Battlegrounds","sz":2,"new":0}];
  var byId = {}; Z.forEach(function (z) { byId[z.id] = z; });
  // true geography: UiMapAssignment rectangles, normalized to the landmass crop
  var GEO = {"zones":{"ek":[{"a":"33","u":14.53,"v":77.25,"w":58.56,"h":21.56},{"a":"1","u":18.38,"v":40.29,"w":45.19,"h":16.64},{"a":"16591","u":52.26,"v":53.41,"w":44.51,"h":16.39},{"a":"85","u":7.07,"v":1.19,"w":41.47,"h":15.27},{"a":"28","u":31.07,"v":3.58,"w":39.47,"h":14.53},{"a":"139","u":55.59,"v":1.94,"w":39.47,"h":14.53},{"a":"130","u":3.23,"v":12.2,"w":38.53,"h":14.19},{"a":"11","u":38.47,"v":31.53,"w":37.95,"h":13.97},{"a":"47","u":49.35,"v":13.21,"w":35.34,"h":13.01},{"a":"45","u":42.86,"v":21.32,"w":33.04,"h":12.17},{"a":"40","u":7.2,"v":68.28,"w":32.11,"h":11.82},{"a":"12","u":20.8,"v":60.88,"w":31.85,"h":11.73},{"a":"4","u":46.29,"v":74.2,"w":30.75,"h":11.32},{"a":"267","u":25.1,"v":18.61,"w":29.36,"h":10.81},{"a":"46","u":37.34,"v":56.28,"w":26.87,"h":9.9},{"a":"36","u":27.71,"v":13.05,"w":25.68,"h":9.46},{"a":"38","u":53.2,"v":43.39,"w":25.32,"h":9.32},{"a":"10","u":27.26,"v":69.89,"w":24.77,"h":9.12},{"a":"41","u":42.54,"v":70.65,"w":22.93,"h":8.44},{"a":"3","u":53.97,"v":50.5,"w":22.84,"h":8.41},{"a":"8","u":55.3,"v":69.41,"w":21.06,"h":7.75},{"a":"51","u":37.86,"v":51.56,"w":20.48,"h":7.54},{"a":"44","u":50.32,"v":64.11,"w":19.93,"h":7.34},{"a":"1519","u":19.09,"v":61.17,"w":15.96,"h":5.88},{"a":"1497","u":26.87,"v":11.13,"w":8.82,"h":3.25},{"a":"1537","u":41.44,"v":43.8,"w":7.27,"h":2.68}],"kal":[{"a":"17","u":21.94,"v":45.9,"w":69.77,"h":29.64},{"a":"618","u":42.18,"v":15.54,"w":48.87,"h":20.76},{"a":"357","u":2.53,"v":63.36,"w":47.86,"h":20.33},{"a":"440","u":41.5,"v":78.75,"w":47.5,"h":20.18},{"a":"148","u":19.74,"v":16.42,"w":45.1,"h":19.16},{"a":"215","u":22.93,"v":51.81,"w":42.36,"h":17.99},{"a":"331","u":28.3,"v":32.48,"w":39.7,"h":16.86},{"a":"361","u":28.71,"v":21.69,"w":39.6,"h":16.82},{"a":"14","u":53.51,"v":45.04,"w":36.41,"h":15.46},{"a":"15","u":46.72,"v":61.89,"w":36.15,"h":15.36},{"a":"141","u":13.73,"v":1.08,"w":35.06,"h":14.88},{"a":"16","u":62.55,"v":29.54,"w":34.91,"h":14.83},{"a":"406","u":17.66,"v":40.19,"w":33.62,"h":14.28},{"a":"405","u":10.84,"v":50.99,"w":30.96,"h":13.15},{"a":"400","u":42.97,"v":70.37,"w":30.3,"h":12.87},{"a":"490","u":36.33,"v":79.14,"w":25.46,"h":10.82},{"a":"1377","u":22.52,"v":79.11,"w":23.99,"h":10.19},{"a":"616","u":46.34,"v":25.32,"w":23.92,"h":10.15},{"a":"493","u":49.51,"v":15.72,"w":15.89,"h":6.76},{"a":"16651","u":26.05,"v":61.31,"w":14.11,"h":5.99},{"a":"1637","u":65.34,"v":43.0,"w":9.65,"h":4.1},{"a":"1657","u":19.76,"v":8.06,"w":7.3,"h":3.1},{"a":"1638","u":36.43,"v":56.7,"w":7.2,"h":3.06}]},"aspect":{"ek":0.3682,"kal":0.4248}};
  var CONT = { ek: { name: "Eastern Kingdoms" }, kal: { name: "Kalimdor" } };
  var BGS = ["2597", "3277", "3358"];
  var NEWZ = ["16593", "16591", "16606", "16651"];
  var css = ".atlas-btn{position:fixed;right:16px;top:74px;z-index:900;display:flex;flex-direction:column;align-items:center;gap:.25rem;width:52px;height:52px;justify-content:center;color:#e5cc80;background:rgba(13,22,38,.95);border:1px solid rgba(229,204,128,.7);border-radius:2px;cursor:pointer;box-shadow:0 2px 14px rgba(0,0,0,.55)}" +
    ".atlas-btn span{font:700 .5rem/1 var(--heading,inherit);letter-spacing:.12em;text-transform:uppercase}" +
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
    ".atlas-geo{position:relative;height:calc(100vh - 130px);min-height:420px;margin:0 auto;background:radial-gradient(ellipse at 50% 40%, rgba(20,32,54,.65), rgba(5,9,18,0) 70%)}" +
".atlas-g{position:absolute;cursor:pointer;border:1px solid rgba(139,147,167,.16);border-radius:2px;overflow:hidden;background:#0b1322;padding:0}" +
".atlas-g img{position:absolute;inset:0;width:100%;height:100%;object-fit:fill;opacity:.8;transition:opacity .12s}" +
".atlas-g:hover{border-color:#e5cc80;z-index:60!important;box-shadow:0 0 0 1px rgba(229,204,128,.4),0 4px 18px rgba(0,0,0,.55)}" +
".atlas-g:hover img{opacity:1}" +
".atlas-g b{position:absolute;left:0;right:0;bottom:0;padding:.25rem .35rem;font:600 .6rem/1.1 var(--heading,inherit);color:#e8e2d0;background:linear-gradient(transparent,rgba(5,9,18,.9));opacity:0;transition:opacity .12s}" +
".atlas-g:hover b{opacity:1}" +
".atlas-g .nb{position:absolute;top:.2rem;left:.2rem;font:700 .5rem/1 var(--heading,inherit);color:#0d1626;background:#e5cc80;border-radius:2px;padding:.14rem .24rem}" +
".atlas-g.city{border:1px solid rgba(229,204,128,.75);background:rgba(229,204,128,.28);border-radius:50%;min-width:11px;min-height:11px}" +
".atlas-g.city:hover{background:#e5cc80}" +
".atlas-g.city b{left:110%;right:auto;bottom:-30%;background:rgba(5,9,18,.92);border:1px solid rgba(229,204,128,.4);border-radius:2px;padding:.2rem .35rem;white-space:nowrap;font-size:.58rem}" +
    ".atlas-view{max-width:1100px;margin:0 auto}" +
    ".atlas-view img{display:block;width:100%;max-width:1002px;margin:0 auto;border:1px solid rgba(139,147,167,.3);border-radius:2px}" +
    ".atlas-meta{max-width:1002px;margin:.6rem auto 0;color:#8b93a7;font-size:.8rem}";
  var st = document.createElement("style"); st.textContent = css; document.head.appendChild(st);
  var btn = document.createElement("button"); btn.type = "button"; btn.className = "atlas-btn";
  btn.innerHTML = '<svg width="24" height="24" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.2" aria-hidden="true"><path d="M1 3.5 5.5 2l5 1.5L15 2v10.5L10.5 14l-5-1.5L1 14zM5.5 2v10.5M10.5 3.5V14"/></svg><span>Map</span>';
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
      var zs = GEO.zones[view.cont] || [];
      var tiles2 = zs.map(function (g) {
        var z = byId[g.a];
        if (!z) return "";
        var city = {"1519":1,"1537":1,"1497":1,"1637":1,"1638":1,"1657":1}[g.a] === 1;
        return '<button type="button" class="atlas-g' + (city ? " city" : "") + '" data-z="' + z.id +
          '" style="left:' + g.u + '%;top:' + g.v + '%;width:' + g.w + '%;height:' + g.h + '%">' +
          (city ? "" : '<img loading="lazy" src="/map/img/' + z.id + '.jpg" alt="">') +
          (z["new"] && !city ? '<i class="nb">NEW</i>' : "") +
          "<b>" + esc(z.n) + "</b></button>";
      }).join("");
      ov.innerHTML = crumb() + '<div class="atlas-geo" style="aspect-ratio:' + GEO.aspect[view.cont] + '">' + tiles2 + "</div>";
    } else {
      // Azeroth: both continents in the ocean at their UiMapAssignment positions
      function contInner(key) {
        return (GEO.zones[key] || []).map(function (g) {
          var z = byId[g.a];
          if (!z || g.w < 5) return "";
          return '<img loading="lazy" src="/map/img/' + z.id + '.jpg" alt="" style="left:' + g.u + '%;top:' + g.v + '%;width:' + g.w + '%;height:' + g.h + '%">';
        }).join("");
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
