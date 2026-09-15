/* Top menu sections: each menu item gets a small dropdown of the places inside that page.
 * Hover or keyboard focus opens it on desktop; the arrow button opens it on touch screens. */
(function () {
  "use strict";
  var nav = document.querySelector("nav.top .top-nav");
  if (!nav) return;
  var brand = document.querySelector("nav.top .brand");
  var root = brand ? brand.getAttribute("href") : "./";
  if (root.charAt(root.length - 1) !== "/") root += "/";

  var MENUS = {
    ladder: { path: "", label: "The ladder", items: [
      ["Progression", "?ladder=progression"], ["Levelling", "?ladder=levelling"], ["Hardcore", "?ladder=hardcore"],
      ["PvP", "?ladder=pvp"], ["Professions", "?ladder=professions"], ["Guilds", "?ladder=guilds"], ["The Wire", "#wire"]] },
    forge: { path: "plan/", label: "The Forge", items: [
      ["Race and class", "#race"], ["Talents", "#talents"], ["Legacy tree", "#legacy"], ["Gear and stats", "#gear"],
      ["Consumables", "#consumables"], ["Name and share", "#share"], ["Raid composer", "#composer"]] },
    database: { path: "codex/", label: "Database", items: [
      ["Search", "#dbs"], ["The Legacy system", "#legacy"], ["Spells", "#unseen"], ["Class changes", "#classes"],
      ["The new world", "#world"], ["Roadmap", "#roadmap"], ["Systems", "#systems"]] },
    news: { path: "news/", label: "News", items: [["All headlines", ""], ["The Wire on the ladder", "WIRE"]] }
  };
  function keyFor(el) {
    var t = (el.textContent || "").trim().toLowerCase();
    if (t.indexOf("ladder") !== -1) return "ladder";
    if (t.indexOf("forge") !== -1) return "forge";
    if (t.indexOf("database") !== -1) return "database";
    if (t.indexOf("news") !== -1) return "news";
    return "";
  }
  var here = (nav.querySelector(".phase") || {}).textContent || "";
  var hereKey = keyFor({ textContent: here });
  var uid = 0;

  Array.prototype.slice.call(nav.children).forEach(function (el) {
    if (el.classList.contains("discord") || el.id === "gear" || el.id === "phase-chip") return;
    var key = keyFor(el), m = MENUS[key];
    if (!m) return;
    var isHere = key === hereKey;
    var dd = document.createElement("div");
    dd.className = "mdd" + (isHere ? " here" : "");
    el.parentNode.insertBefore(dd, el);
    dd.appendChild(el);
    var btn = document.createElement("button");
    btn.type = "button";
    btn.className = "mdd-btn";
    btn.setAttribute("aria-expanded", "false");
    btn.setAttribute("aria-label", m.label + " sections");
    btn.innerHTML = '<svg viewBox="0 0 10 6" width="10" height="6" aria-hidden="true"><path d="M1 1l4 4 4-4" fill="none" stroke="currentColor" stroke-width="1.6"/></svg>';
    var menu = document.createElement("div");
    menu.className = "mdd-menu";
    menu.id = "mdd-menu-" + (++uid);
    btn.setAttribute("aria-controls", menu.id);
    menu.innerHTML = m.items.map(function (it) {
      var href = it[1] === "WIRE" ? root + "#wire" : (isHere && it[1].charAt(0) === "#" ? it[1] : root + m.path + it[1]);
      return '<a href="' + href + '">' + it[0] + "</a>";
    }).join("");
    dd.appendChild(btn);
    dd.appendChild(menu);
    btn.addEventListener("click", function (e) {
      e.stopPropagation();
      var open = !dd.classList.contains("open");
      closeAll();
      dd.classList.toggle("open", open);
      btn.setAttribute("aria-expanded", String(open));
    });
    menu.addEventListener("click", function () { closeAll(); });
  });
  function closeAll() {
    Array.prototype.slice.call(nav.querySelectorAll(".mdd.open")).forEach(function (d) {
      d.classList.remove("open");
      var b = d.querySelector(".mdd-btn");
      if (b) b.setAttribute("aria-expanded", "false");
    });
  }
  document.addEventListener("click", function (e) { if (!e.target.closest || !e.target.closest(".mdd")) closeAll(); });
  document.addEventListener("keydown", function (e) { if (e.key === "Escape") closeAll(); });
})();
