/* The corner card: feedback and donations, sitewide.
 * Slides in once per visit after real reading time or a long scroll, goes
 * away with one click, and stays away for weeks once dismissed or used.
 * Set DONATE_URL to show the donate button; empty hides it. */
(function () {
  "use strict";
  var DONATE_URL = "https://paypal.me/MikalSteenMonslaup";
  var FEEDBACK_URL = "https://discord.gg/DZUZj66zh";  // the guild Discord
  var HUSH_KEY = "fr-support-hush", HUSH_DAYS = 21, USED_DAYS = 45;

  function hushed() {
    try {
      var t = +localStorage.getItem(HUSH_KEY) || 0;
      return t && Date.now() < t;
    } catch (e) { return false; }
  }
  function hush(days) {
    try { localStorage.setItem(HUSH_KEY, String(Date.now() + days * 864e5)); } catch (e) { }
  }
  if (hushed()) return;

  var css = [
    "#fr-support{position:fixed;right:1rem;bottom:1rem;z-index:80;width:min(19rem,calc(100vw - 2rem));",
    "background:linear-gradient(180deg,rgba(7,50,74,.97),rgba(5,30,45,.99));border:1px solid rgba(229,204,128,.45);",
    "border-radius:10px;box-shadow:0 12px 40px rgba(0,0,0,.6);padding:.85rem .95rem .9rem;color:#f4f0eb;",
    "font:500 .82rem/1.45 Archivo,'Segoe UI',sans-serif;transform:translateY(0);opacity:1;transition:transform .35s ease,opacity .35s ease}",
    "#fr-support.fr-in{transform:translateY(120%);opacity:0}",
    "#fr-support h3{display:flex;align-items:center;gap:.5rem;margin:0 0 .3rem;font:600 .85rem Poppins,'Segoe UI',sans-serif;letter-spacing:.03em;color:#e5cc80}",
    "#fr-support h3 img{width:1.5rem;height:1.5rem}",
    "#fr-support p{margin:0 0 .65rem;color:#cfd8dc}",
    "#fr-support .fr-acts{display:flex;gap:.45rem;flex-wrap:wrap}",
    "#fr-support a{flex:1;min-width:7rem;text-align:center;text-decoration:none;font:600 .74rem/1 Poppins,'Segoe UI',sans-serif;",
    "letter-spacing:.04em;border-radius:6px;padding:.55rem .6rem;border:1px solid rgba(0,175,215,.35);color:#f4f0eb;background:rgba(0,0,0,.28)}",
    "#fr-support a:hover{border-color:#e5cc80;color:#fff}",
    "#fr-support a.fr-don{background:#e5cc80;border-color:#e5cc80;color:#1a1204}",
    "#fr-support a.fr-don:hover{background:#f0dc9a;color:#000}",
    "#fr-support .fr-x{position:absolute;right:.3rem;top:.25rem;width:1.7rem;height:1.7rem;border:0;background:none;",
    "color:#9fb0bb;font-size:1.15rem;line-height:1;cursor:pointer;border-radius:6px}",
    "#fr-support .fr-x:hover{color:#fff;background:rgba(255,255,255,.08)}",
    "@media print{#fr-support{display:none}}",
    "@media (prefers-reduced-motion: reduce){#fr-support{transition:none}}"
  ].join("");

  function show() {
    if (document.getElementById("fr-support")) return;
    var st = document.createElement("style");
    st.textContent = css;
    document.head.appendChild(st);
    var el = document.createElement("aside");
    el.id = "fr-support";
    el.className = "fr-in";
    el.setAttribute("aria-label", "Feedback and support");
    el.innerHTML =
      '<button type="button" class="fr-x" aria-label="Dismiss">×</button>' +
      '<h3><img src="/mark.svg" alt="">Fan-run. Ad-free. Beta-fast.</h3>' +
      "<p>ForeverRank is rebuilt after every beta build, for free, by people who should be sleeping. " +
      "Tell us what is wrong or missing" + (DONATE_URL ? ", or toss a coin at the hosting bill." : ".") + "</p>" +
      '<div class="fr-acts">' +
      '<a href="' + FEEDBACK_URL + '" rel="noopener" data-act="feedback">Give feedback</a>' +
      (DONATE_URL ? '<a class="fr-don" href="' + DONATE_URL + '" target="_blank" rel="noopener" data-act="donate">Buy the smith a mead</a>' : "") +
      "</div>";
    document.body.appendChild(el);
    requestAnimationFrame(function () { requestAnimationFrame(function () { el.classList.remove("fr-in"); }); });
    el.querySelector(".fr-x").addEventListener("click", function () {
      hush(HUSH_DAYS);
      el.classList.add("fr-in");
      setTimeout(function () { el.remove(); }, 400);
    });
    el.querySelectorAll("a[data-act]").forEach(function (a) {
      a.addEventListener("click", function () { hush(USED_DAYS); });
    });
  }

  // earn the corner: half a minute of reading, or a real scroll (the first
  // seconds don't count, so an anchor jump on load is not "a real scroll")
  var armed = false, t0 = Date.now();
  function arm() {
    if (armed) return;
    armed = true;
    show();
  }
  setTimeout(arm, 30000);
  window.addEventListener("scroll", function onScroll() {
    if (Date.now() - t0 > 8000 && window.scrollY > 1200) {
      window.removeEventListener("scroll", onScroll);
      arm();
    }
  }, { passive: true });
})();
