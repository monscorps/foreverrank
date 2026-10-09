/* The Atlas v8: navigates like the game map on Forever's own painted art.
 * World, then continent, then zone. Left-click descends, right-click or Esc
 * climbs back out, X closes. Hotspots come straight from UiMapAssignment.
 * Zone levels, flight paths, towns and dungeon doors load lazily from
 * map/atlas.json (tools/build_atlas.py, read from the beta client). */
(function () {
  "use strict";
  var Z = [{"id":"16606","n":"Darkspear Islands","c":"New in Forever","sz":4,"new":1},{"id":"16591","n":"Riverglades","c":"New in Forever","sz":20,"new":1},{"id":"16651","n":"Shen'dralas","c":"New in Forever","sz":6,"new":1},{"id":"16593","n":"Zephras Isle","c":"New in Forever","sz":27,"new":1},{"id":"36","n":"Alterac Mountains","c":"Eastern Kingdoms","sz":21,"new":0},{"id":"45","n":"Arathi Highlands","c":"Eastern Kingdoms","sz":24,"new":0},{"id":"3","n":"Badlands","c":"Eastern Kingdoms","sz":17,"new":0},{"id":"4","n":"Blasted Lands","c":"Eastern Kingdoms","sz":9,"new":0},{"id":"46","n":"Burning Steppes","c":"Eastern Kingdoms","sz":13,"new":0},{"id":"41","n":"Deadwind Pass","c":"Eastern Kingdoms","sz":10,"new":0},{"id":"1","n":"Dun Morogh","c":"Eastern Kingdoms","sz":25,"new":0},{"id":"10","n":"Duskwood","c":"Eastern Kingdoms","sz":20,"new":0},{"id":"139","n":"Eastern Plaguelands","c":"Eastern Kingdoms","sz":34,"new":0},{"id":"12","n":"Elwynn Forest","c":"Eastern Kingdoms","sz":26,"new":0},{"id":"267","n":"Hillsbrad Foothills","c":"Eastern Kingdoms","sz":16,"new":0},{"id":"38","n":"Loch Modan","c":"Eastern Kingdoms","sz":16,"new":0},{"id":"44","n":"Redridge Mountains","c":"Eastern Kingdoms","sz":16,"new":0},{"id":"51","n":"Searing Gorge","c":"Eastern Kingdoms","sz":12,"new":0},{"id":"130","n":"Silverpine Forest","c":"Eastern Kingdoms","sz":24,"new":0},{"id":"33","n":"Stranglethorn Vale","c":"Eastern Kingdoms","sz":45,"new":0},{"id":"8","n":"Swamp of Sorrows","c":"Eastern Kingdoms","sz":15,"new":0},{"id":"47","n":"The Hinterlands","c":"Eastern Kingdoms","sz":22,"new":0},{"id":"85","n":"Tirisfal Glades","c":"Eastern Kingdoms","sz":30,"new":0},{"id":"28","n":"Western Plaguelands","c":"Eastern Kingdoms","sz":17,"new":0},{"id":"40","n":"Westfall","c":"Eastern Kingdoms","sz":19,"new":0},{"id":"11","n":"Wetlands","c":"Eastern Kingdoms","sz":28,"new":0},{"id":"331","n":"Ashenvale","c":"Kalimdor","sz":42,"new":0},{"id":"16","n":"Azshara","c":"Kalimdor","sz":31,"new":0},{"id":"148","n":"Darkshore","c":"Kalimdor","sz":17,"new":0},{"id":"405","n":"Desolace","c":"Kalimdor","sz":21,"new":0},{"id":"14","n":"Durotar","c":"Kalimdor","sz":28,"new":0},{"id":"15","n":"Dustwallow Marsh","c":"Kalimdor","sz":28,"new":0},{"id":"361","n":"Felwood","c":"Kalimdor","sz":18,"new":0},{"id":"357","n":"Feralas","c":"Kalimdor","sz":35,"new":0},{"id":"493","n":"Moonglade","c":"Kalimdor","sz":5,"new":0},{"id":"616","n":"Mount Hyjal","c":"Kalimdor","sz":9,"new":1},{"id":"215","n":"Mulgore","c":"Kalimdor","sz":29,"new":0},{"id":"1377","n":"Silithus","c":"Kalimdor","sz":21,"new":0},{"id":"406","n":"Stonetalon Mountains","c":"Kalimdor","sz":19,"new":0},{"id":"440","n":"Tanaris","c":"Kalimdor","sz":25,"new":0},{"id":"141","n":"Teldrassil","c":"Kalimdor","sz":24,"new":0},{"id":"17","n":"The Barrens","c":"Kalimdor","sz":44,"new":0},{"id":"400","n":"Thousand Needles","c":"Kalimdor","sz":22,"new":0},{"id":"490","n":"Un'Goro Crater","c":"Kalimdor","sz":12,"new":0},{"id":"618","n":"Winterspring","c":"Kalimdor","sz":18,"new":0},{"id":"1657","n":"Darnassus","c":"Cities","sz":5,"new":0},{"id":"1537","n":"Ironforge","c":"Cities","sz":0,"new":0},{"id":"1637","n":"Orgrimmar","c":"Cities","sz":0,"new":0},{"id":"1519","n":"Stormwind City","c":"Cities","sz":2,"new":0},{"id":"1638","n":"Thunder Bluff","c":"Cities","sz":4,"new":0},{"id":"1497","n":"Undercity","c":"Cities","sz":0,"new":0},{"id":"2597","n":"Alterac Valley","c":"Battlegrounds","sz":26,"new":0},{"id":"3358","n":"Arathi Basin","c":"Battlegrounds","sz":7,"new":0},{"id":"3277","n":"Warsong Gulch","c":"Battlegrounds","sz":2,"new":0}];
  var GEO = {"zones":{"kal":[{"a":"17","u":23.55,"v":46.0,"w":65.78,"h":28.89},{"a":"618","u":42.63,"v":16.41,"w":46.07,"h":20.24},{"a":"357","u":5.25,"v":63.02,"w":45.12,"h":19.82},{"a":"440","u":41.99,"v":78.02,"w":44.78,"h":19.67},{"a":"148","u":21.47,"v":17.27,"w":42.51,"h":18.67},{"a":"215","u":24.48,"v":51.76,"w":39.93,"h":17.54},{"a":"331","u":29.54,"v":32.92,"w":37.43,"h":16.44},{"a":"361","u":29.93,"v":22.4,"w":37.33,"h":16.4},{"a":"14","u":53.31,"v":45.16,"w":34.32,"h":15.08},{"a":"15","u":46.91,"v":61.59,"w":34.08,"h":14.97},{"a":"141","u":15.81,"v":2.31,"w":33.05,"h":14.51},{"a":"16","u":61.83,"v":30.06,"w":32.91,"h":14.46},{"a":"406","u":19.51,"v":40.43,"w":31.69,"h":13.92},{"a":"405","u":13.09,"v":50.97,"w":29.19,"h":12.82},{"a":"400","u":43.37,"v":69.86,"w":28.56,"h":12.55},{"a":"490","u":37.11,"v":78.41,"w":24.0,"h":10.54},{"a":"1377","u":24.1,"v":78.38,"w":22.62,"h":9.93},{"a":"616","u":46.55,"v":25.94,"w":22.55,"h":9.89},{"a":"493","u":49.53,"v":16.59,"w":14.97,"h":6.59},{"a":"16651","u":27.42,"v":61.03,"w":13.3,"h":5.84},{"a":"1637","u":64.46,"v":43.18,"w":9.1,"h":4.0},{"a":"1657","u":21.5,"v":9.12,"w":6.88,"h":3.02},{"a":"1638","u":37.21,"v":56.54,"w":6.78,"h":2.98}],"ek":[{"a":"33","u":17.09,"v":76.49,"w":54.35,"h":20.96},{"a":"1","u":20.65,"v":40.56,"w":41.94,"h":16.18},{"a":"16591","u":52.1,"v":53.32,"w":41.31,"h":15.93},{"a":"85","u":10.16,"v":2.54,"w":38.49,"h":14.85},{"a":"28","u":32.43,"v":4.87,"w":36.63,"h":14.13},{"a":"139","u":55.19,"v":3.27,"w":36.63,"h":14.13},{"a":"130","u":6.59,"v":13.25,"w":35.76,"h":13.8},{"a":"11","u":39.3,"v":32.04,"w":35.22,"h":13.59},{"a":"47","u":49.4,"v":14.23,"w":32.79,"h":12.65},{"a":"45","u":43.38,"v":22.12,"w":30.67,"h":11.83},{"a":"40","u":10.28,"v":67.77,"w":29.8,"h":11.49},{"a":"12","u":22.9,"v":60.58,"w":29.56,"h":11.4},{"a":"4","u":46.55,"v":73.53,"w":28.54,"h":11.01},{"a":"267","u":26.89,"v":19.48,"w":27.25,"h":10.51},{"a":"46","u":38.25,"v":56.11,"w":24.94,"h":9.62},{"a":"36","u":29.32,"v":14.07,"w":23.83,"h":9.19},{"a":"38","u":52.97,"v":43.57,"w":23.5,"h":9.07},{"a":"10","u":28.9,"v":69.33,"w":22.99,"h":8.87},{"a":"41","u":43.08,"v":70.07,"w":21.28,"h":8.21},{"a":"3","u":53.69,"v":50.49,"w":21.19,"h":8.18},{"a":"8","u":54.92,"v":68.87,"w":19.54,"h":7.54},{"a":"51","u":38.73,"v":51.51,"w":19.0,"h":7.33},{"a":"44","u":50.3,"v":63.71,"w":18.5,"h":7.13},{"a":"1519","u":21.31,"v":60.86,"w":14.81,"h":5.71},{"a":"1497","u":28.54,"v":12.21,"w":8.18,"h":3.16},{"a":"1537","u":42.06,"v":43.98,"w":6.74,"h":2.6}]},"aspect":{"kal":0.6593,"ek":0.5786}};
  var byId = {}; Z.forEach(function (z) { byId[z.id] = z; });
  var CONT = { ek: { name: "Eastern Kingdoms" }, kal: { name: "Kalimdor" } };
  var BGS = ["2597", "3277", "3358"];
  var NEWZ = ["16593", "16591", "16606", "16651"];
  var CITY = { "1519": 1, "1537": 1, "1497": 1, "1637": 1, "1638": 1, "1657": 1 };
  var FAC = { A: "Alliance", H: "Horde", AH: "both factions" };
  var ART = "?b=70291";  // the client build the continent and world art were cut from (tools/build_maps.py --wago)
  var css = ".atlas-pill svg{margin-right:.35rem;vertical-align:-2px}" +
    ".atlas{position:fixed;inset:0;z-index:950;background:rgba(5,9,18,.99);overflow:auto;padding:1.1rem;-webkit-overflow-scrolling:touch;--al:#5aa0f0;--ho:#e8574a;--both:#e5cc80}" +
    ".atlas[hidden]{display:none}" +
    ".atlas-head{display:flex;align-items:center;gap:.6rem;max-width:1100px;margin:0 auto .8rem}" +
    ".atlas-crumb{display:flex;flex-wrap:wrap;align-items:center;gap:.4rem;font:600 .8rem/1.3 var(--heading,inherit);color:#8b93a7}" +
    ".atlas-crumb button{font:inherit;color:#e5cc80;background:none;border:0;padding:0;cursor:pointer;letter-spacing:.04em}" +
    ".atlas-crumb b{color:#e8e2d0;letter-spacing:.04em}" +
    ".atlas-crumb i{font-style:normal;color:#3d4658}" +
    ".atlas-hint{margin-left:auto;color:#5c657a;font-size:.68rem}" +
    ".atlas-x{flex:none;color:#8b93a7;background:none;border:1px solid rgba(139,147,167,.4);border-radius:2px;padding:.35rem .7rem;cursor:pointer;font-size:1rem}" +
    ".atlas-x:hover{color:#e5cc80;border-color:#e5cc80}" +
    // Azeroth: Forever's world map, both continents clickable
    ".atlas-az{position:relative;width:min(100%,max(300px,calc((100vh - 250px) * 1.5)));aspect-ratio:1.5;margin:0 auto;background:#0b1322 center/100% 100% no-repeat;border:1px solid rgba(139,147,167,.3);border-radius:2px}" +
    ".az-cont{position:absolute;background:none;border:1px solid transparent;border-radius:2px;padding:0;cursor:pointer;transition:border-color .15s,background .15s}" +
    ".az-cont:hover,.az-cont:focus-visible{border-color:#e5cc80;background:rgba(229,204,128,.08)}" +
    ".az-cont b{position:absolute;left:50%;bottom:.4rem;transform:translateX(-50%);font:700 .7rem/1 var(--heading,inherit);letter-spacing:.1em;text-transform:uppercase;color:#e8e2d0;background:rgba(5,9,18,.82);border:1px solid rgba(229,204,128,.4);border-radius:2px;padding:.3rem .5rem;white-space:nowrap}" +
    ".az-cont:hover b{color:#e5cc80}" +
    ".atlas-row{max-width:1100px;margin:.9rem auto 0}" +
    ".atlas-row h4{font:600 .7rem/1 var(--heading,inherit);letter-spacing:.1em;text-transform:uppercase;color:#8b93a7;margin:0 0 .45rem}" +
    ".atlas-tiles{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:.5rem}" +
    ".atlas-t{position:relative;cursor:pointer;border:1px solid rgba(139,147,167,.25);border-radius:2px;overflow:hidden;background:#0d1626;padding:0}" +
    ".atlas-t img{display:block;width:100%;height:86px;object-fit:cover;opacity:.85;transition:transform .15s,opacity .15s}" +
    ".atlas-t:hover{border-color:#e5cc80;z-index:2}.atlas-t:hover img{opacity:1;transform:scale(1.06)}" +
    ".atlas-t b{position:absolute;left:0;right:0;bottom:0;padding:.35rem .45rem;font:600 .64rem/1.15 var(--heading,inherit);color:#e8e2d0;background:linear-gradient(transparent,rgba(5,9,18,.94))}" +
    ".atlas-t b em,.atlas-l em{font-style:normal;color:#e5cc80;font-variant-numeric:tabular-nums}" +
    ".atlas-t .nb{position:absolute;top:.3rem;left:.3rem;font:700 .55rem/1 var(--heading,inherit);letter-spacing:.05em;color:#0d1626;background:#e5cc80;border-radius:2px;padding:.18rem .3rem}" +
    // continent: map left, controls, details and zone list right (stacked on phones)
    ".atlas-cv{display:grid;grid-template-columns:auto 270px;grid-template-areas:'map ctl' 'map info' 'map list';gap:.7rem 1rem;justify-content:center;align-items:start;max-width:1100px;margin:0 auto}" +
    ".atlas-cv>.atlas-geo{grid-area:map}.atlas-ctl{grid-area:ctl}.atlas-cv>.atlas-info{grid-area:info}.atlas-list{grid-area:list}" +
    ".atlas-geo{position:relative;height:max(320px,min(calc(100vh - 170px),calc((100vw - 340px) / var(--ar))));aspect-ratio:var(--ar);background:#0b1322 center/100% 100% no-repeat;border:1px solid rgba(139,147,167,.3);border-radius:2px}" +
    ".atlas-g{position:absolute;z-index:57;cursor:pointer;border:1px solid rgba(232,226,208,.16);border-radius:2px;background:none;padding:0;transition:border-color .12s,background .12s}" +
    ".atlas-g:hover,.atlas-g:focus-visible{border-color:#e5cc80;background:rgba(229,204,128,.1);z-index:60!important;box-shadow:0 0 0 1px rgba(229,204,128,.35),0 4px 18px rgba(0,0,0,.35)}" +
    ".atlas-g b{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);padding:.25rem .45rem;font:700 .68rem/1.1 var(--heading,inherit);letter-spacing:.05em;color:#f4ead0;background:rgba(5,9,18,.88);border:1px solid rgba(229,204,128,.45);border-radius:2px;white-space:nowrap;opacity:0;transition:opacity .12s;pointer-events:none;z-index:2}" +
    ".atlas-g:hover b,.atlas-g:focus-visible b{opacity:1}" +
    ".atlas-g .nb{position:absolute;top:.2rem;left:.2rem;font:700 .5rem/1 var(--heading,inherit);color:#0d1626;background:#e5cc80;border-radius:2px;padding:.14rem .24rem}" +
    ".atlas-g .lvb{display:none;position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);font:700 .6rem/1 var(--heading,inherit);font-style:normal;font-variant-numeric:tabular-nums;color:#f4ead0;background:rgba(5,9,18,.74);border-radius:2px;padding:.16rem .28rem;white-space:nowrap;pointer-events:none}" +
    ".show-lv .atlas-g .lvb{display:block}" +
    ".filt .atlas-g.fit{border-color:rgba(229,204,128,.85);background:rgba(229,204,128,.14)}" +
    ".filt .atlas-g.fit .lvb{display:block;background:#e5cc80;color:#14100a}" +
    ".filt .atlas-g.dim .lvb{opacity:.4}" +
    ".atlas-g.city{border:1px solid rgba(229,204,128,.75);background:rgba(229,204,128,.28);border-radius:50%;min-width:11px;min-height:11px}" +
    ".atlas-g.city:hover{background:#e5cc80}" +
    ".atlas-g.city b{left:110%;top:auto;bottom:-30%;transform:none;font-size:.58rem}" +
    // flight lines, towns and pins over the art
    ".atlas-lines{position:absolute;inset:0;width:100%;height:100%;pointer-events:none;z-index:55;filter:drop-shadow(0 0 1px rgba(0,0,0,.95))}" +
    ".atlas-lines line{stroke-width:1.6px;vector-effect:non-scaling-stroke;stroke-linecap:round;display:none}" +
    ".atlas-lines .r-A{stroke:var(--al)}.atlas-lines .r-H{stroke:var(--ho)}.atlas-lines .r-AH{stroke:var(--both)}" +
    ".fly-A .r-A,.fly-A .r-AH,.fly-H .r-H,.fly-H .r-AH,.fly-B line{display:inline}" +
    ".atlas-town{display:none;position:absolute;z-index:56;transform:translate(-3px,-50%);font:600 .56rem/1 var(--heading,inherit);color:#f4ead0;text-shadow:0 0 3px #000,0 0 2px #000;white-space:nowrap;pointer-events:none}" +
    ".atlas-town i{display:inline-block;width:5px;height:5px;border-radius:50%;background:#f4ead0;box-shadow:0 0 0 1px rgba(0,0,0,.8);margin-right:3px;vertical-align:1px}" +
    ".atlas-town.k0{color:#d6cfbd;font-weight:500}.atlas-town.k0 i{width:4px;height:4px}" +
    ".show-town .atlas-town{display:block}" +
    ".atlas-pin{position:absolute;z-index:70;width:22px;height:22px;margin:-11px 0 0 -11px;padding:0;border:0;background:none;cursor:pointer}" +
    ".atlas-pin::before{content:'';position:absolute;left:50%;top:50%;width:9px;height:9px;margin:-4.5px 0 0 -4.5px;border-radius:50%;background:var(--c,#e5cc80);box-shadow:0 0 0 1.5px #0b1322,0 0 0 2.5px rgba(244,234,208,.55);transition:transform .12s}" +
    ".atlas-pin:hover::before,.atlas-pin:focus-visible::before,.atlas-pin.sel::before{transform:scale(1.45)}" +
    ".atlas-pin.f-A{--c:var(--al)}.atlas-pin.f-H{--c:var(--ho)}.atlas-pin.f-AH{--c:var(--both)}" +
    ".atlas-geo .pin-fm{display:none}" +
    ".fly-A .pin-fm.f-A,.fly-A .pin-fm.f-AH,.fly-H .pin-fm.f-H,.fly-H .pin-fm.f-AH,.fly-B .pin-fm{display:block}" +
    ".pin-dn::before{border-radius:1px;width:8px;height:8px;margin:-4px 0 0 -4px;background:#14100a;box-shadow:0 0 0 2px #e5cc80,0 0 0 3px rgba(0,0,0,.7);transform:rotate(45deg)}" +
    ".pin-dn.raid::before{box-shadow:0 0 0 2px #c58cf0,0 0 0 3px rgba(0,0,0,.7)}" +
    ".pin-dn:hover::before,.pin-dn:focus-visible::before,.pin-dn.sel::before{transform:rotate(45deg) scale(1.45)}" +
    ".atlas-geo .pin-dn{display:none}.show-dng .pin-dn{display:block}" +
    // side panel
    ".atlas-ctl{display:flex;flex-direction:column;gap:.6rem}" +
    ".atlas-ctl>div,.atlas-my{display:flex;flex-wrap:wrap;align-items:center;gap:.4rem .6rem}" +
    ".atlas-ctl>div>span,.atlas-my>span,.atlas-list h4,.atlas-facts h4{margin:0;font:600 .66rem/1 var(--heading,inherit);letter-spacing:.1em;text-transform:uppercase;color:#8b93a7}" +
    ".atlas-seg{display:inline-flex;flex-wrap:wrap;padding:3px;gap:2px;border-radius:8px;background:rgba(0,0,0,.3);border:1px solid rgba(139,147,167,.3)}" +
    ".atlas-seg button{display:inline-flex;align-items:center;height:1.9rem;cursor:pointer;padding:0 .6rem;border:0;border-radius:6px;background:none;font:600 .7rem/1 var(--heading,inherit);color:#b3c1c8;white-space:nowrap;transition:color .15s,background .15s}" +
    ".atlas-seg button:hover:not(.on){color:#fff;background:rgba(255,255,255,.05)}" +
    ".atlas-seg button.on{color:#14100a;background:linear-gradient(180deg,#f0dfa8,#d9b96a);box-shadow:0 1px 6px rgba(0,0,0,.35)}" +
    ".atlas-seg button i,.atlas-dot{display:inline-block;flex:none;width:.45rem;height:.45rem;border-radius:50%;background:var(--c);margin-right:.35rem;box-shadow:0 0 0 1px rgba(0,0,0,.6)}" +
    ".atlas-dot.f-A{--c:var(--al)}.atlas-dot.f-H{--c:var(--ho)}.atlas-dot.f-AH{--c:var(--both)}.atlas-dot.f-{--c:transparent;box-shadow:0 0 0 1px rgba(139,147,167,.6)}" +
    ".atlas-my input{width:4.4rem;height:2rem;box-sizing:border-box;background:#0d1626;border:1px solid rgba(139,147,167,.35);border-radius:6px;color:#e8e2d0;font:600 16px/1 var(--heading,inherit);padding:0 .5rem}" +
    ".atlas-my input:focus{outline:none;border-color:#e5cc80}" +
    ".atlas-my small{color:#8b93a7;font-size:.7rem}" +
    ".atlas-info{background:#0d1626;border:1px solid rgba(139,147,167,.3);border-radius:2px;padding:.6rem .75rem;color:#aab2c3;font-size:.78rem;line-height:1.45}" +
    ".atlas-info.on{position:relative;border-color:rgba(229,204,128,.45);padding-right:2rem}" +
    ".atlas-ix{position:absolute;top:.25rem;right:.3rem;width:1.6rem;height:1.6rem;padding:0;border:0;background:none;color:#8b93a7;font-size:1rem;cursor:pointer}.atlas-ix:hover{color:#e5cc80}" +
    ".atlas-info b{color:#e8e2d0}.atlas-info a{color:#e5cc80}.atlas-info p{margin:.3rem 0 0}" +
    ".atlas-info .k{display:inline-flex;align-items:center;color:#8b93a7;font-size:.72rem}" +
    ".atlas-info ul{margin:.3rem 0 0;padding:0;list-style:none}.atlas-info li{display:flex;justify-content:space-between;gap:.6rem;border-top:1px solid rgba(139,147,167,.12);padding:.18rem 0}" +
    ".atlas-info li em{font-style:normal;color:#e5cc80;white-space:nowrap;font-variant-numeric:tabular-nums}" +
    ".atlas-list ol{list-style:none;margin:.45rem 0 0;padding:0;display:grid;gap:2px}" +
    ".atlas-l{display:flex;align-items:center;gap:.1rem;width:100%;text-align:left;cursor:pointer;background:rgba(13,22,38,.7);border:1px solid transparent;border-radius:2px;padding:.32rem .5rem;color:#d6d0bf;font:500 .76rem/1.2 var(--body,inherit)}" +
    ".atlas-l span{flex:1;min-width:0}" +
    ".atlas-l:hover,.atlas-l:focus-visible{border-color:#e5cc80;color:#fff}" +
    ".filt .atlas-l.fit{border-color:rgba(229,204,128,.6);background:rgba(229,204,128,.1)}.filt .atlas-l.dim{opacity:.45}" +
    ".atlas-src{color:#6d7689;font-size:.7rem;line-height:1.45;margin:.7rem 0 0}" +
    // zone
    ".atlas-view{max-width:1002px;margin:0 auto}" +
    ".atlas-zmap{position:relative}" +
    ".atlas-zmap img{display:block;width:100%;height:auto;border:1px solid rgba(139,147,167,.3);border-radius:2px}" +
    ".atlas-view>.atlas-info{margin-top:.6rem}" +
    ".atlas-facts{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:.4rem 1.2rem;margin-top:.6rem;color:#aab2c3;font-size:.8rem;line-height:1.45}" +
    ".atlas-facts h3{grid-column:1/-1;display:flex;flex-wrap:wrap;align-items:center;gap:.5rem;margin:0;font:700 1rem/1.2 var(--heading,inherit);color:#e8e2d0}" +
    ".atlas-facts h3 em{font:700 .72rem/1 var(--heading,inherit);font-style:normal;color:#14100a;background:#e5cc80;border-radius:2px;padding:.22rem .4rem}" +
    ".atlas-facts h3 small{font:600 .72rem/1 var(--heading,inherit);color:#8b93a7}" +
    ".atlas-facts p{margin:0}.atlas-facts a{color:#e5cc80}" +
    ".atlas-facts ul{list-style:none;margin:.35rem 0 0;padding:0}.atlas-facts li{padding:.2rem 0;border-top:1px solid rgba(139,147,167,.12)}" +
    ".atlas-facts li b{color:#e8e2d0;font-weight:600}" +
    ".atlas-facts .full{grid-column:1/-1}.atlas-facts li.far{opacity:.62}" +
    "@media (max-width:820px){.atlas-cv{display:flex;flex-direction:column;gap:.7rem}.atlas-ctl{order:-1}" +
    ".atlas-geo{height:auto;width:100%}.atlas-info.on{position:sticky;bottom:0;z-index:80;box-shadow:0 -6px 18px rgba(0,0,0,.5)}.atlas-hint{display:none}" +
    ".az-cont b{font-size:.58rem;letter-spacing:.04em;padding:.25rem .4rem}}";
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
  var ov = document.createElement("div"); ov.className = "atlas"; ov.hidden = true;
  ov.setAttribute("role", "dialog"); ov.setAttribute("aria-label", "World atlas");
  document.body.appendChild(ov);
  var view = { lvl: "world", cont: null, zone: null };

  // what the viewer last chose to show: kept in this browser only
  var OPT = { lv: 1, dng: 1, town: 0, fly: "", my: "" };
  try { var saved = JSON.parse(localStorage.getItem("atlas-opt") || "null"); if (saved) for (var k in OPT) if (k in saved) OPT[k] = saved[k]; } catch (e) {}
  if (!/^(|A|H|B)$/.test(OPT.fly)) OPT.fly = "";
  if (!/^[1-9][0-9]?$/.test(OPT.my) || +OPT.my > 60) OPT.my = "";
  function keep() { try { localStorage.setItem("atlas-opt", JSON.stringify(OPT)); } catch (e) {} }

  // zone levels, flights, towns and doors: fetched the first time the Atlas opens
  var D = null, TX = {}, OUT = {}, asked = false, failed = false;
  function load() {
    if (D || asked) return;
    asked = true;
    fetch("/map/atlas.json", { cache: "no-cache" }).then(function (r) { return r.ok ? r.json() : null; }).catch(function () { return null; }).then(function (j) {
      if (!j || !j.zones) { asked = false; failed = true; var b = ov.querySelector(".atlas-info"); if (b) b.innerHTML = hint(); return; }
      failed = false;
      D = j;
      D.taxi.forEach(function (t) { TX[t.id] = t; OUT[t.id] = []; });
      D.routes.forEach(function (r) {
        if (r[2] !== null) OUT[r[0]].push([r[1], r[2]]);
        if (r[3] !== null) OUT[r[1]].push([r[0], r[3]]);
      });
      if (!ov.hidden) { var y = ov.scrollTop; draw(); ov.scrollTop = y; }
    });
  }

  function esc(s) { return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/"/g, "&quot;"); }
  function zd(id) { return (D && D.zones[id]) || null; }
  function contOf(id) {
    for (var k in GEO.zones) if (GEO.zones[k].some(function (g) { return g.a === id; })) return k;
    return null;
  }
  function lvText(id) {
    var z = zd(id);
    if (!z || !z.lv) return "";
    return z.lv[0] === z.lv[1] ? String(z.lv[0]) : z.lv[0] + "\u2013" + z.lv[1];
  }
  function fits(id) {
    var z = zd(id), my = parseInt(OPT.my, 10);
    return !!(z && z.lv && my >= z.lv[0] && my <= z.lv[1]);
  }
  function money(c) {
    if (!c) return "free";
    var g = Math.floor(c / 10000), s = Math.floor(c % 10000 / 100), cp = c % 100;
    return [g ? g + "g" : "", s ? s + "s" : "", cp ? cp + "c" : ""].filter(Boolean).join(" ");
  }
  function pos(p) { return "left:" + p[0] + "%;top:" + p[1] + "%"; }
  function routeFac(a, b) {
    var f = "";
    if (TX[a].f.indexOf("A") > -1 && TX[b].f.indexOf("A") > -1) f += "A";
    if (TX[a].f.indexOf("H") > -1 && TX[b].f.indexOf("H") > -1) f += "H";
    return f;
  }

  function tile(z) {
    var lv = lvText(z.id);
    return '<button type="button" class="atlas-t" data-z="' + z.id + '">' +
      '<img loading="lazy" src="/map/img/' + z.id + '.jpg" alt="">' +
      (z["new"] ? '<i class="nb">NEW</i>' : "") + "<b>" + esc(z.n) + (lv ? " <em>" + lv + "</em>" : "") + "</b></button>";
  }
  function crumb() {
    var parts = ['<button type="button" data-lvl="world">Azeroth</button>'];
    if (view.lvl !== "world" && view.cont) parts.push("<i>/</i>" + (view.lvl === "cont" ? "<b>" + CONT[view.cont].name + "</b>" : '<button type="button" data-lvl="cont">' + CONT[view.cont].name + "</button>"));
    if (view.lvl === "zone") parts.push("<i>/</i><b>" + esc(view.zone.n) + "</b>");
    return '<div class="atlas-head"><div class="atlas-crumb">' + parts.join("") + "</div>" +
      '<span class="atlas-hint">Left-click to enter, right-click to step out</span>' +
      '<button type="button" class="atlas-x" aria-label="Close">\u00d7</button></div>';
  }

  // ---- pins: flight masters and dungeon doors ----
  function pinFm(t, p) {
    return '<button type="button" class="atlas-pin pin-fm f-' + t.f + '" data-tx="' + t.id + '" style="' + pos(p) + '" aria-label="' + esc(t.n) + ", " + FAC[t.f] + ' flight master"></button>';
  }
  function pinDn(d, i, p) {
    return '<button type="button" class="atlas-pin pin-dn' + (d.raid ? " raid" : "") + '" data-dn="' + i + '" style="' + pos(p) + '" aria-label="' + esc(d.n) + (d.raid ? " (raid)" : "") + ' entrance"></button>';
  }
  function hint() {
    return D ? '<span class="k">Hover or tap a pin for details.</span>' :
      '<span class="k">' + (failed ? "Levels and flight paths did not load. Close and reopen the Atlas to try again." : "Loading levels and flight paths\u2026") + "</span>";
  }
  function infoFm(id) {
    var t = TX[id];
    var out = (OUT[id] || []).slice().sort(function (a, b) { return a[1] - b[1] || (TX[a[0]].n < TX[b[0]].n ? -1 : 1); });
    var h = '<b>' + esc(t.n) + "</b>" + (t.w ? ' <span class="k">' + esc(t.w) + "</span>" : "") +
      '<p><span class="k"><i class="atlas-dot f-' + t.f + '"></i>' + (t.f === "AH" ? "Flight master for both factions" : FAC[t.f] + " flight master") + "</span></p>";
    if (out.length) {
      h += '<ul>' + out.map(function (o) {
        var d = TX[o[0]];
        return "<li><span>" + (t.f === "AH" && d.f !== "AH" ? '<i class="atlas-dot f-' + d.f + '" title="' + FAC[d.f] + '"></i>' : "") + esc(d.n) +
          (d.w && d.w !== t.w ? ' <span class="k">' + esc(d.w) + "</span>" : "") + "</span><em>" + money(o[1]) + "</em></li>";
      }).join("") + "</ul>";
    } else h += "<p>No flights from here in this build yet.</p>";
    if (t.inf) h += '<p class="k">The client gives this flight master no faction flag; the faction comes from its flight mount.</p>';
    return h;
  }
  function infoDn(i) {
    var d = D.dungeons[i];
    var h = "<b>" + esc(d.n) + '</b> <span class="k">' + (d.raid ? "raid" : "dungeon") + (d.w ? " in " + esc(d.w) : "") + (d.lv ? ", client tuning level " + d.lv : "") + "</span>" +
      "<p>" + (d.src === "cmangos" ? "Door: an entrance trigger in the client that Classic server data names as this raid." : d.src === "players" ? "Door: where players' games put " + (d.who || "the dungeon's quest giver") + "; the client has no entrance point for it yet, so the entrance is inferred." : "Door: where the client sends your ghost to run back in.") + "</p>";
    if (d.loot && d.loot.length) h += "<p>" + d.loot.map(function (n) {
      return '<a href="/world/?loot=' + encodeURIComponent(n) + '">' + esc(d.loot.length > 1 ? n.replace(/^[^:]*:\s*/, "") : "Loot table") + " \u203a</a>";
    }).join(" \u00b7 ") + "</p>";
    return h;
  }
  function showInfo(pin) {
    var box = ov.querySelector(".atlas-info");
    if (!box || !D) return;
    var was = ov.querySelector(".atlas-pin.sel");
    if (was) was.classList.remove("sel");
    pin.classList.add("sel");
    box.innerHTML = '<button type="button" class="atlas-ix" aria-label="Close details">\u00d7</button>' +
      (pin.hasAttribute("data-tx") ? infoFm(+pin.getAttribute("data-tx")) : infoDn(+pin.getAttribute("data-dn")));
    box.classList.add("on");
  }

  // ---- continent ----
  function geoClasses() {
    return "atlas-geo" + (OPT.lv ? " show-lv" : "") + (OPT.dng ? " show-dng" : "") + (OPT.town ? " show-town" : "") +
      (OPT.fly ? " fly-" + OPT.fly : "");
  }
  function drawCont() {
    var key = view.cont, zs = GEO.zones[key] || [];
    var spots = zs.map(function (g) {
      var z = byId[g.a];
      if (!z) return "";
      var city = CITY[g.a] === 1, lv = lvText(g.a);
      return '<button type="button" class="atlas-g' + (city ? " city" : "") + (lv && OPT.my ? (fits(g.a) ? " fit" : " dim") : "") + '" data-z="' + z.id +
        '" style="left:' + g.u + "%;top:" + g.v + "%;width:" + g.w + "%;height:" + g.h + '%">' +
        (z["new"] && !city ? '<i class="nb">NEW</i>' : "") +
        (lv ? '<em class="lvb">' + lv + "</em>" : "") +
        "<b>" + esc(z.n) + (lv ? " \u00b7 " + lv : "") + "</b></button>";
    }).join("");
    var layer = "";
    if (D) {
      var lines = D.routes.map(function (r) {
        var a = TX[r[0]], b = TX[r[1]], f = routeFac(r[0], r[1]);
        if (a.c !== key || b.c !== key || !f) return "";
        return '<line class="r-' + f + '" x1="' + a.p[0] + '" y1="' + a.p[1] + '" x2="' + b.p[0] + '" y2="' + b.p[1] + '"/>';
      }).join("");
      layer += '<svg class="atlas-lines" viewBox="0 0 100 100" preserveAspectRatio="none" aria-hidden="true">' + lines + "</svg>";
      layer += D.towns.map(function (t) {
        return t.c === key ? '<span class="atlas-town k' + t.k + '" style="' + pos(t.p) + '"><i></i>' + esc(t.n) + "</span>" : "";
      }).join("");
      layer += D.dungeons.map(function (d, i) { return d.c === key ? pinDn(d, i, d.p) : ""; }).join("");
      layer += D.taxi.map(function (t) { return t.c === key ? pinFm(t, t.p) : ""; }).join("");
    }
    var seg = function (v, label, c) {
      return '<button type="button" data-fly="' + v + '" class="' + (OPT.fly === v ? "on" : "") + '" aria-pressed="' + (OPT.fly === v) + '">' + (c ? '<i style="--c:var(' + c + ')"></i>' : "") + label + "</button>";
    };
    var tog = function (k, label) {
      return '<button type="button" data-opt="' + k + '" class="' + (OPT[k] ? "on" : "") + '" aria-pressed="' + !!OPT[k] + '">' + label + "</button>";
    };
    var ctl = '<div class="atlas-ctl">' +
      '<div><span>Show</span><div class="atlas-seg" role="group" aria-label="Show on the map">' + tog("lv", "Levels") + tog("dng", "Dungeons") + tog("town", "Towns") + "</div></div>" +
      '<div><span>Flight paths</span><div class="atlas-seg" role="group" aria-label="Flight paths">' + seg("", "Off") + seg("A", "Alliance", "--al") + seg("H", "Horde", "--ho") + seg("B", "Both") + "</div></div>" +
      '<label class="atlas-my"><span>Your level</span><input type="number" min="1" max="60" inputmode="numeric" placeholder="1\u201360" value="' + esc(OPT.my) + '"><small class="atlas-fitn"></small></label></div>';
    var rows = zs.filter(function (g) { return byId[g.a] && !CITY[g.a]; }).map(function (g) { return g.a; });
    rows.sort(function (a, b) {
      var x = zd(a), y = zd(b), xl = x && x.lv ? x.lv : [99, 99], yl = y && y.lv ? y.lv : [99, 99];
      return xl[0] - yl[0] || xl[1] - yl[1] || (byId[a].n < byId[b].n ? -1 : 1);
    });
    var list = '<div class="atlas-list"><h4>Zones by level</h4><ol>' + rows.map(function (id) {
      var z = zd(id), f = z && z.f ? z.f : "", lv = lvText(id);
      return '<li><button type="button" class="atlas-l' + (lv && OPT.my ? (fits(id) ? " fit" : " dim") : (OPT.my ? " dim" : "")) + '" data-z="' + id + '">' +
        '<i class="atlas-dot f-' + f + '" title="' + (f ? FAC[f] : "Open to both factions") + '"></i><span>' + esc(byId[id].n) + "</span><em>" + (lv || "\u2013") + "</em></button></li>";
    }).join("") + "</ol>" + srcNote() + "</div>";
    ov.innerHTML = crumb() + '<div class="atlas-cv' + (OPT.my ? " filt" : "") + '"><div class="' + geoClasses() + '" style="--ar:' + GEO.aspect[key] + ";background-image:url(/map/img/cont-" + key + ".jpg" + ART + ')">' + spots + layer + "</div>" +
      ctl + '<div class="atlas-info" aria-live="polite">' + hint() + "</div>" + list + "</div>";
    countFits();
  }
  function srcNote() {
    var b = D ? D.build : "";
    var un = D && D.unplaced && D.unplaced.length ? " The new dungeons the client lists so far (" + D.unplaced.map(esc).join(", ") + ") have no door in it yet, so they are not on the map." : "";
    if (D && D.notyet && D.notyet.length) un += " The client has no dungeon at all yet for the other new ones in our loot tables (" + D.notyet.map(esc).join(", ") + ").";
    return '<p class="atlas-src">Read from the beta client' + (b ? ", build " + esc(b) : "") + ". Levels are the range the client gives the places in each zone; one or two far-off places are left out and named on that zone\u2019s map. Starting areas carry no level in the client, so a starting zone\u2019s range begins a few levels in. " +
      "Flight costs are the client\u2019s base prices. Dungeon doors are where the client sends your ghost to run back in." + un + " Map art: Forever\u2019s own repainted maps from the client.</p>";
  }
  function countFits() {
    var n = ov.querySelector(".atlas-fitn");
    if (!n) return;
    if (!OPT.my || !D) { n.textContent = ""; return; }
    var c = ov.querySelectorAll(".atlas-l.fit").length;
    n.textContent = c ? c + (c === 1 ? " zone fits" : " zones fit") : "no zone here fits";
  }
  function applyLevel() {
    var cv = ov.querySelector(".atlas-cv");
    if (!cv) return;
    cv.classList.toggle("filt", !!OPT.my);
    ov.querySelectorAll(".atlas-g[data-z], .atlas-l[data-z]").forEach(function (el) {
      var id = el.getAttribute("data-z"), has = !!lvText(id);
      el.classList.toggle("fit", !!OPT.my && has && fits(id));
      el.classList.toggle("dim", !!OPT.my && !(has && fits(id)) && !el.classList.contains("city"));
    });
    countFits();
  }

  // ---- zone ----
  function drawZone() {
    var z = view.zone, id = z.id, d = zd(id);
    var pins = "", fms = [], dns = [];
    if (D) {
      D.dungeons.forEach(function (x, i) { if (x.zp && x.zp[id]) { pins += pinDn(x, i, x.zp[id]); dns.push(x); } });
      D.taxi.forEach(function (t) { if (t.zp && t.zp[id]) { pins += pinFm(t, t.zp[id]); fms.push(t); } });
    }
    var own = function (t) { return (t.w && (z.n.indexOf(t.w) === 0 || t.w.indexOf(z.n) === 0)) || z.n.indexOf(t.n) === 0; };
    fms.sort(function (a, b) { return (own(b) ? 1 : 0) - (own(a) ? 1 : 0); });
    // a door is this zone's unless the data puts it in another zone the Atlas has (Blackrock Mountain counts for both its zones)
    var ownD = function (x) { return !x.z || x.z === id; };
    dns.sort(function (a, b) { return (ownD(b) ? 1 : 0) - (ownD(a) ? 1 : 0); });
    var lv = lvText(id), ck = contOf(id);
    var meta = [ck ? CONT[ck].name : z.c === "New in Forever" ? "its own map" : z.c, z["new"] ? "new in Forever" : "", d && d.f ? FAC[d.f] : ""].filter(Boolean).join(" \u00b7 ");
    var facts = '<h3>' + esc(z.n) + (lv ? "<em>Levels " + lv + "</em>" : "") + "<small>" + esc(meta) + "</small></h3>";
    if (D) {
      var n = d ? d.n : z.sz;
      if (d && d.lv) {
        facts += '<p class="full">Levels ' + lv + " come from the beta client (build " + esc(D.build) + "): the range of the levels it gives " + d.of + " of this zone\u2019s " + n + " named places." +
          (d.out ? " Left out as far off: " + d.out.map(function (o) { return esc(o[0]) + " (" + o[1] + ")"; }).join(", ") + "." : "") + "</p>";
      } else if (!CITY[id] && z.c !== "Battlegrounds") {
        facts += '<p class="full">' + (n ? n + " named places in the client, none with a level yet." : "The client gives this zone no level yet.") + "</p>";
      } else if (n) facts += '<p class="full">' + n + " named places in the client.</p>";
      if (fms.length) facts += "<div><h4>Flight masters on this map</h4><ul>" + fms.map(function (t) {
        var to = [];
        (OUT[t.id] || []).forEach(function (o) { var nm = esc(TX[o[0]].n); if (to.indexOf(nm) < 0) to.push(nm); });
        return '<li' + (own(t) ? "" : ' class="far"') + '><i class="atlas-dot f-' + t.f + '"></i><b>' + esc(t.n) + "</b>" + (own(t) || !t.w ? "" : ", " + esc(t.w)) + " \u00b7 " + (t.f === "AH" ? "both factions" : FAC[t.f]) +
          (to.length ? "<br><span>to " + to.join(", ") + "</span>" : "<br><span>no flights yet</span>") + "</li>";
      }).join("") + "</ul></div>";
      if (dns.length) facts += "<div><h4>Dungeon doors on this map</h4><ul>" + dns.map(function (x) {
        return "<li" + (ownD(x) ? "" : ' class="far"') + "><b>" + esc(x.n) + "</b>" + (ownD(x) || !x.w ? "" : ", " + esc(x.w)) + (x.raid ? " \u00b7 raid" : "") + (x.lv ? " \u00b7 client tuning level " + x.lv : "") +
          (x.loot ? "<br>" + x.loot.map(function (l) { return '<a href="/world/?loot=' + encodeURIComponent(l) + '">' + esc(x.loot.length > 1 ? l.replace(/^[^:]*:\s*/, "") : "Loot table") + " \u203a</a>"; }).join(" \u00b7 ") : "") + "</li>";
      }).join("") + "</ul></div>";
    } else if (z.sz) facts += '<p class="full">' + z.sz + " named places in the client.</p>";
    ov.innerHTML = crumb() + '<div class="atlas-view"><div class="atlas-zmap"><img src="/map/img/' + id + '.jpg" alt="' + esc(z.n) + ' map" width="900" height="600">' + pins + "</div>" +
      (pins ? '<div class="atlas-info" aria-live="polite">' + hint() + "</div>" : "") +
      '<div class="atlas-facts">' + facts + "</div></div>";
  }

  // ---- world ----
  function newNote() {
    if (!D || !NEWZ.some(function (id) { return lvText(id); })) return "";
    var zi = zd("16593");   // Zephras Isle: its starting area has no level, Blizzard says 1-12
    return '<p class="atlas-src">Levels read from the beta client, build ' + esc(D.build) + ": the range it gives each zone\u2019s places." +
      (zi && zi.lv && zi.lv[0] > 1 ? " Starting areas carry no level there, so Zephras Isle starts at " + zi.lv[0] + " (Blizzard: levels 1\u201312)." : "") + "</p>";
  }
  function drawWorld() {
    ov.innerHTML = crumb() +
      '<div class="atlas-az" style="background-image:url(/map/img/world.jpg' + ART + ')">' +
      '<button type="button" class="az-cont" data-cont="kal" style="left:11.5%;top:10%;width:26.5%;height:77%"><b>Kalimdor</b></button>' +
      '<button type="button" class="az-cont" data-cont="ek" style="left:66%;top:7%;width:25%;height:77%"><b>Eastern Kingdoms</b></button>' +
      "</div>" +
      '<div class="atlas-row"><h4>New in Forever</h4><div class="atlas-tiles">' + NEWZ.map(function (id) { return tile(byId[id]); }).join("") + "</div>" + newNote() + "</div>" +
      '<div class="atlas-row"><h4>Battlegrounds</h4><div class="atlas-tiles">' + BGS.map(function (id) { return tile(byId[id]); }).join("") + "</div></div>";
  }

  function draw() {
    if (view.lvl === "zone") drawZone();
    else if (view.lvl === "cont") drawCont();
    else drawWorld();
  }
  function go() { draw(); ov.scrollTop = 0; }
  function close() { ov.hidden = true; document.body.style.overflow = ""; if (location.hash === "#atlas") { try { history.replaceState(null, "", location.pathname + location.search); } catch (e) {} } }
  function up() {
    if (view.lvl === "zone") { view.lvl = view.cont ? "cont" : "world"; view.zone = null; go(); }
    else if (view.lvl === "cont") { view.lvl = "world"; view.cont = null; go(); }
    else close();
  }
  function openAtlas() { view = { lvl: "world", cont: null, zone: null }; go(); ov.hidden = false; document.body.style.overflow = "hidden"; load(); }
  btn.addEventListener("click", function (e) { e.preventDefault(); openAtlas(); });
  if (location.hash === "#atlas") openAtlas();
  window.addEventListener("hashchange", function () { if (location.hash === "#atlas") openAtlas(); });
  ov.addEventListener("contextmenu", function (e) { if (e.target.closest && e.target.closest("input")) return; e.preventDefault(); up(); });
  ov.addEventListener("click", function (e) {
    var t = e.target.closest && e.target.closest("button");
    if (!t) return;
    if (t.className === "atlas-x") { close(); return; }
    if (t.className === "atlas-ix") {
      var box = t.parentNode, was = ov.querySelector(".atlas-pin.sel");
      if (was) was.classList.remove("sel");
      box.classList.remove("on"); box.innerHTML = hint(); return;
    }
    if (t.hasAttribute("data-tx") || t.hasAttribute("data-dn")) { showInfo(t); return; }
    if (t.hasAttribute("data-opt")) {
      var k = t.getAttribute("data-opt");
      OPT[k] = OPT[k] ? 0 : 1; keep();
      t.classList.toggle("on", !!OPT[k]); t.setAttribute("aria-pressed", String(!!OPT[k]));
      ov.querySelector(".atlas-geo").className = geoClasses();
      return;
    }
    if (t.hasAttribute("data-fly")) {
      OPT.fly = t.getAttribute("data-fly"); keep();
      t.parentNode.querySelectorAll("button").forEach(function (b) { var on = b === t; b.classList.toggle("on", on); b.setAttribute("aria-pressed", String(on)); });
      ov.querySelector(".atlas-geo").className = geoClasses();
      return;
    }
    if (t.hasAttribute("data-lvl")) {
      var l = t.getAttribute("data-lvl");
      if (l === "world") { view = { lvl: "world", cont: null, zone: null }; }
      else { view.lvl = "cont"; view.zone = null; }
      go(); return;
    }
    if (t.hasAttribute("data-cont")) { view.lvl = "cont"; view.cont = t.getAttribute("data-cont"); go(); return; }
    if (t.hasAttribute("data-z")) {
      var z = byId[t.getAttribute("data-z")];
      if (!z) return;
      view.cont = contOf(z.id);
      view.lvl = "zone"; view.zone = z; go();
    }
  });
  // desktop: hovering or tabbing onto a pin shows it too
  ov.addEventListener("mouseover", function (e) { var p = e.target.closest && e.target.closest(".atlas-pin"); if (p && !p.classList.contains("sel")) showInfo(p); });
  ov.addEventListener("focusin", function (e) { if (e.target.classList && e.target.classList.contains("atlas-pin")) showInfo(e.target); });
  ov.addEventListener("input", function (e) {
    if (!e.target.matches || !e.target.matches(".atlas-my input")) return;
    var v = parseInt(e.target.value, 10);
    OPT.my = v >= 1 && v <= 60 ? String(v) : ""; keep();
    applyLevel();
  });
  document.addEventListener("keydown", function (e) { if (e.key === "Escape" && !ov.hidden) up(); });
})();
