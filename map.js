/* The Atlas: every zone map from beta client build 1.60.1.69876. One corner button, zones clickable, more per zone as the beta reveals it. */
(function () {
  "use strict";
  var Z = [{"id":"16606","n":"Darkspear Islands","c":"New in Forever","sz":4,"new":1},{"id":"16591","n":"Riverglades","c":"New in Forever","sz":19,"new":1},{"id":"16651","n":"Shen'dralas","c":"New in Forever","sz":6,"new":1},{"id":"16593","n":"Zephras Isle","c":"New in Forever","sz":27,"new":1},{"id":"36","n":"Alterac Mountains","c":"Eastern Kingdoms","sz":21,"new":0},{"id":"45","n":"Arathi Highlands","c":"Eastern Kingdoms","sz":24,"new":0},{"id":"3","n":"Badlands","c":"Eastern Kingdoms","sz":17,"new":0},{"id":"4","n":"Blasted Lands","c":"Eastern Kingdoms","sz":9,"new":0},{"id":"46","n":"Burning Steppes","c":"Eastern Kingdoms","sz":13,"new":0},{"id":"41","n":"Deadwind Pass","c":"Eastern Kingdoms","sz":10,"new":0},{"id":"1","n":"Dun Morogh","c":"Eastern Kingdoms","sz":25,"new":0},{"id":"10","n":"Duskwood","c":"Eastern Kingdoms","sz":20,"new":0},{"id":"139","n":"Eastern Plaguelands","c":"Eastern Kingdoms","sz":34,"new":0},{"id":"12","n":"Elwynn Forest","c":"Eastern Kingdoms","sz":26,"new":0},{"id":"267","n":"Hillsbrad Foothills","c":"Eastern Kingdoms","sz":16,"new":0},{"id":"38","n":"Loch Modan","c":"Eastern Kingdoms","sz":16,"new":0},{"id":"44","n":"Redridge Mountains","c":"Eastern Kingdoms","sz":16,"new":0},{"id":"51","n":"Searing Gorge","c":"Eastern Kingdoms","sz":12,"new":0},{"id":"130","n":"Silverpine Forest","c":"Eastern Kingdoms","sz":24,"new":0},{"id":"33","n":"Stranglethorn Vale","c":"Eastern Kingdoms","sz":45,"new":0},{"id":"8","n":"Swamp of Sorrows","c":"Eastern Kingdoms","sz":15,"new":0},{"id":"47","n":"The Hinterlands","c":"Eastern Kingdoms","sz":22,"new":0},{"id":"85","n":"Tirisfal Glades","c":"Eastern Kingdoms","sz":30,"new":0},{"id":"28","n":"Western Plaguelands","c":"Eastern Kingdoms","sz":17,"new":0},{"id":"40","n":"Westfall","c":"Eastern Kingdoms","sz":19,"new":0},{"id":"11","n":"Wetlands","c":"Eastern Kingdoms","sz":28,"new":0},{"id":"331","n":"Ashenvale","c":"Kalimdor","sz":42,"new":0},{"id":"16","n":"Azshara","c":"Kalimdor","sz":31,"new":0},{"id":"148","n":"Darkshore","c":"Kalimdor","sz":17,"new":0},{"id":"405","n":"Desolace","c":"Kalimdor","sz":21,"new":0},{"id":"14","n":"Durotar","c":"Kalimdor","sz":28,"new":0},{"id":"15","n":"Dustwallow Marsh","c":"Kalimdor","sz":28,"new":0},{"id":"361","n":"Felwood","c":"Kalimdor","sz":18,"new":0},{"id":"357","n":"Feralas","c":"Kalimdor","sz":35,"new":0},{"id":"493","n":"Moonglade","c":"Kalimdor","sz":5,"new":0},{"id":"616","n":"Mount Hyjal","c":"Kalimdor","sz":9,"new":1},{"id":"215","n":"Mulgore","c":"Kalimdor","sz":29,"new":0},{"id":"1377","n":"Silithus","c":"Kalimdor","sz":21,"new":0},{"id":"406","n":"Stonetalon Mountains","c":"Kalimdor","sz":19,"new":0},{"id":"440","n":"Tanaris","c":"Kalimdor","sz":25,"new":0},{"id":"141","n":"Teldrassil","c":"Kalimdor","sz":24,"new":0},{"id":"17","n":"The Barrens","c":"Kalimdor","sz":44,"new":0},{"id":"400","n":"Thousand Needles","c":"Kalimdor","sz":22,"new":0},{"id":"490","n":"Un'Goro Crater","c":"Kalimdor","sz":12,"new":0},{"id":"618","n":"Winterspring","c":"Kalimdor","sz":18,"new":0},{"id":"1657","n":"Darnassus","c":"Cities","sz":5,"new":0},{"id":"1537","n":"Ironforge","c":"Cities","sz":0,"new":0},{"id":"1637","n":"Orgrimmar","c":"Cities","sz":0,"new":0},{"id":"1519","n":"Stormwind City","c":"Cities","sz":2,"new":0},{"id":"1638","n":"Thunder Bluff","c":"Cities","sz":4,"new":0},{"id":"1497","n":"Undercity","c":"Cities","sz":0,"new":0},{"id":"2597","n":"Alterac Valley","c":"Battlegrounds","sz":26,"new":0},{"id":"3358","n":"Arathi Basin","c":"Battlegrounds","sz":7,"new":0},{"id":"3277","n":"Warsong Gulch","c":"Battlegrounds","sz":2,"new":0}];
  var GROUPS = ["All", "New in Forever", "Eastern Kingdoms", "Kalimdor", "Cities", "Battlegrounds"];
  var css = ".atlas-btn{position:fixed;right:18px;bottom:18px;z-index:900;display:flex;align-items:center;gap:.45rem;font:700 .78rem/1 var(--heading,inherit);letter-spacing:.1em;text-transform:uppercase;color:#e5cc80;background:rgba(13,22,38,.94);border:1px solid rgba(229,204,128,.65);border-radius:2px;padding:.7rem .95rem;cursor:pointer;box-shadow:0 2px 14px rgba(0,0,0,.5)}" +
    ".atlas-btn:hover{border-color:#e5cc80}" +
    ".atlas{position:fixed;inset:0;z-index:950;background:rgba(5,9,18,.96);overflow:auto;padding:1.2rem;-webkit-overflow-scrolling:touch}" +
    ".atlas[hidden]{display:none}" +
    ".atlas-head{display:flex;align-items:center;gap:.8rem;max-width:1180px;margin:0 auto .9rem}" +
    ".atlas-head b{font-size:1.15rem;color:#e8e2d0}.atlas-head span{color:#8b93a7;font-size:.78rem}" +
    ".atlas-x{margin-left:auto;font-size:1.1rem;color:#8b93a7;background:none;border:1px solid rgba(139,147,167,.4);border-radius:2px;padding:.35rem .7rem;cursor:pointer}.atlas-x:hover{color:#e5cc80;border-color:#e5cc80}" +
    ".atlas-chips{display:flex;flex-wrap:wrap;gap:.3rem;max-width:1180px;margin:0 auto .9rem}" +
    ".atlas-chips button{font:600 .68rem/1 var(--heading,inherit);letter-spacing:.03em;color:#c8cede;background:rgba(0,0,0,.4);border:1px solid rgba(139,147,167,.3);border-radius:2px;padding:.4rem .6rem;cursor:pointer}" +
    ".atlas-chips button.on{color:#e5cc80;border-color:#e5cc80}" +
    ".atlas-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:.7rem;max-width:1180px;margin:0 auto}" +
    ".atlas-z{position:relative;cursor:pointer;border:1px solid rgba(139,147,167,.25);border-radius:2px;overflow:hidden;background:#0d1626;padding:0;text-align:left}" +
    ".atlas-z img{display:block;width:100%;height:140px;object-fit:cover;object-position:center;opacity:.92}" +
    ".atlas-z:hover{border-color:#e5cc80}.atlas-z:hover img{opacity:1}" +
    ".atlas-z b{position:absolute;left:0;right:0;bottom:0;padding:.45rem .55rem;font:600 .74rem/1.2 var(--heading,inherit);color:#e8e2d0;background:linear-gradient(transparent,rgba(5,9,18,.92))}" +
    ".atlas-new{position:absolute;top:.4rem;left:.4rem;font:700 .58rem/1 var(--heading,inherit);letter-spacing:.06em;color:#0d1626;background:#e5cc80;border-radius:2px;padding:.2rem .35rem}" +
    ".atlas-view{max-width:1180px;margin:0 auto}" +
    ".atlas-view img{display:block;width:100%;max-width:1002px;margin:0 auto;border:1px solid rgba(139,147,167,.3);border-radius:2px}" +
    ".atlas-meta{max-width:1002px;margin:.6rem auto 0;color:#8b93a7;font-size:.8rem}" +
    ".atlas-back{font:600 .7rem/1 var(--heading,inherit);letter-spacing:.06em;text-transform:uppercase;color:#e5cc80;background:none;border:1px solid rgba(229,204,128,.5);border-radius:2px;padding:.45rem .7rem;cursor:pointer;margin-bottom:.8rem}";
  var st = document.createElement("style"); st.textContent = css; document.head.appendChild(st);
  var btn = document.createElement("button"); btn.type = "button"; btn.className = "atlas-btn";
  btn.innerHTML = '<svg width="15" height="15" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" aria-hidden="true"><path d="M1 3.5 5.5 2l5 1.5L15 2v10.5L10.5 14l-5-1.5L1 14zM5.5 2v10.5M10.5 3.5V14"/></svg><span>Atlas</span>';
  btn.setAttribute("aria-label", "Open the zone atlas");
  document.body.appendChild(btn);
  var ov = document.createElement("div"); ov.className = "atlas"; ov.hidden = true; document.body.appendChild(ov);
  var cur = { g: "All", z: null };
  function esc(s) { return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;"); }
  function draw() {
    var head = '<div class="atlas-head"><b>The Atlas</b><span>Every zone map in beta client build 1.60.1.69876</span><button type="button" class="atlas-x" aria-label="Close">\u00d7</button></div>';
    if (cur.z) {
      var z = cur.z;
      ov.innerHTML = head + '<div class="atlas-view"><button type="button" class="atlas-back" data-back="1">All zones</button>' +
        '<img src="/map/img/' + z.id + '.jpg" alt="' + esc(z.n) + ' map">' +
        '<p class="atlas-meta"><b style="color:#e8e2d0">' + esc(z.n) + "</b> \u00b7 " + esc(z.c) + (z.sz ? " \u00b7 " + z.sz + " named subzones in the client" : "") +
        (z.new && z.c !== "New in Forever" ? " \u00b7 New in Forever" : "") + ". More lands here as the beta gives it up.</p></div>";
    } else {
      var chips = GROUPS.map(function (g) {
        return '<button type="button" data-g="' + g + '"' + (cur.g === g ? ' class="on"' : "") + ">" + g + "</button>";
      }).join("");
      var grid = Z.filter(function (z) { return cur.g === "All" || z.c === cur.g; }).map(function (z) {
        return '<button type="button" class="atlas-z" data-z="' + z.id + '"><img loading="lazy" src="/map/img/' + z.id + '.jpg" alt="">' +
          (z.new ? '<i class="atlas-new">NEW</i>' : "") + "<b>" + esc(z.n) + "</b></button>";
      }).join("");
      ov.innerHTML = head + '<div class="atlas-chips">' + chips + '</div><div class="atlas-grid">' + grid + "</div>";
    }
  }
  function openAtlas() { cur.z = null; draw(); ov.hidden = false; document.body.style.overflow = "hidden"; }
  btn.addEventListener("click", openAtlas);
  if (location.hash === "#atlas") openAtlas();
  window.addEventListener("hashchange", function () { if (location.hash === "#atlas") openAtlas(); });
  ov.addEventListener("click", function (e) {
    var t = e.target.closest && e.target.closest("button");
    if (!t) return;
    if (t.className === "atlas-x") { ov.hidden = true; document.body.style.overflow = ""; return; }
    if (t.hasAttribute("data-back")) { cur.z = null; draw(); return; }
    if (t.hasAttribute("data-g")) { cur.g = t.getAttribute("data-g"); draw(); return; }
    if (t.hasAttribute("data-z")) {
      var id = t.getAttribute("data-z");
      cur.z = Z.filter(function (z) { return z.id === id; })[0] || null;
      draw(); ov.scrollTop = 0;
    }
  });
  document.addEventListener("keydown", function (e) { if (e.key === "Escape" && !ov.hidden) { ov.hidden = true; document.body.style.overflow = ""; } });
})();
