/* TipKit: one tooltip system for mouse and touch.
 * Mouse: hover tooltip that flips to stay on screen.
 * Touch/pen: a tap opens a bottom sheet, with optional action buttons,
 * because phones have no hover and no right click. */
(function () {
  "use strict";
  var lastPT = (window.matchMedia && matchMedia("(hover: none)").matches) ? "touch" : "mouse";
  document.addEventListener("pointerdown", function (e) { lastPT = e.pointerType || "mouse"; }, true);
  function touchy() {
    return lastPT === "touch" || lastPT === "pen" ||
      (lastPT !== "mouse" && window.matchMedia && matchMedia("(hover: none)").matches);
  }

  var tip = null, tipVisible = false, lastEvt = null;
  function tipEl() {
    if (!tip) {
      tip = document.getElementById("tip") || document.createElement("div");
      if (!tip.parentNode) { tip.id = "tip"; document.body.appendChild(tip); }
    }
    return tip;
  }
  var anchorEl = null;
  function placeAnchor(el) {
    var t = tipEl(), r = el.getBoundingClientRect(), w = t.offsetWidth, h = t.offsetHeight, vw = window.innerWidth, vh = window.innerHeight, pad = 8;
    var x = r.right - 2, y = r.top - h + 2;
    if (x + w > vw - pad) x = r.left - w + 2;
    if (x < pad) x = pad;
    if (y < pad) y = r.bottom - 2;
    if (y + h > vh - pad) y = Math.max(pad, vh - h - pad);
    t.style.left = Math.round(x) + "px";
    t.style.top = Math.round(y) + "px";
  }
  function place(e) {
    if (anchorEl) { placeAnchor(anchorEl); return; }
    if (!tipVisible || !e) return;
    var t = tipEl(), w = t.offsetWidth, h = t.offsetHeight, vw = window.innerWidth, vh = window.innerHeight, pad = 10;
    var x = e.clientX + 16, y = e.clientY + 18;
    if (x + w > vw - pad) x = e.clientX - w - 16;
    if (x < pad) x = Math.max(pad, Math.min(vw - w - pad, e.clientX - w / 2));
    if (y + h > vh - pad) y = e.clientY - h - 14;
    if (y < pad) y = pad;
    t.style.left = Math.round(x) + "px";
    t.style.top = Math.round(y) + "px";
  }
  function show(html, cls, e, anchor) {
    if (!html) return;
    anchorEl = anchor || null;
    var t = tipEl();
    t.className = "tip" + (cls ? " " + cls : "");
    t.innerHTML = html;
    t.hidden = false;
    t.style.display = "block";
    tipVisible = true;
    place(e || lastEvt);
  }
  function hide() {
    anchorEl = null;
    if (!tip) return;
    tip.hidden = true;
    tip.style.display = "none";
    tipVisible = false;
  }
  // Mouse-only hover. htmlFn and clsFn are called fresh each time, so state changes show up.
  // opts.anchor: pin the tip's bottom-left to the element's top-right, like the game does.
  function hover(el, htmlFn, clsFn, opts) {
    var anchored = !!(opts && opts.anchor);
    el.addEventListener("pointerenter", function (e) {
      if (e.pointerType !== "mouse") return;
      lastEvt = e;
      show(htmlFn(el), clsFn ? clsFn(el) : "", e, anchored ? el : null);
    });
    el.addEventListener("pointermove", function (e) {
      if (e.pointerType !== "mouse" || anchored) return;
      lastEvt = e;
      place(e);
    });
    el.addEventListener("pointerleave", function (e) { if (e.pointerType === "mouse") hide(); });
  }

  // ---- bottom sheet ----------------------------------------------------------
  var sheet = null, body = null, acts = null, sheetOwner = null, sheetOnClose = null;
  function sheetEl() {
    if (sheet) return sheet;
    sheet = document.createElement("div");
    sheet.className = "tsheet";
    sheet.hidden = true;
    sheet.setAttribute("role", "dialog");
    sheet.setAttribute("aria-live", "polite");
    sheet.innerHTML = '<div class="ts-grip"></div><button type="button" class="ts-x" aria-label="Close">&times;</button>' +
      '<div class="ts-body"></div><div class="ts-acts"></div>';
    document.body.appendChild(sheet);
    body = sheet.querySelector(".ts-body");
    acts = sheet.querySelector(".ts-acts");
    sheet.querySelector(".ts-x").addEventListener("click", closeSheet);
    var y0 = null, st0 = 0;
    sheet.addEventListener("touchstart", function (e) { y0 = e.touches[0].clientY; st0 = sheet.scrollTop; }, { passive: true });
    sheet.addEventListener("touchend", function (e) {
      // Only a drag that began at the very top closes; dragging to scroll back up must not.
      if (y0 != null && st0 <= 0 && e.changedTouches[0].clientY - y0 > 70) closeSheet();
      y0 = null;
    });
    return sheet;
  }
  // actions: [{label, cls, disabled, onClick}]
  function openSheet(html, actions, opts) {
    opts = opts || {};
    hide();
    var s = sheetEl();
    s.className = "tsheet" + (opts.cls ? " " + opts.cls : "");
    body.innerHTML = html || "";
    acts.innerHTML = "";
    (actions || []).forEach(function (a) {
      var b = document.createElement("button");
      b.type = "button";
      b.className = "ts-act" + (a.cls ? " " + a.cls : "");
      b.textContent = a.label;
      b.disabled = !!a.disabled;
      b.addEventListener("click", function (ev) { ev.stopPropagation(); if (!b.disabled && a.onClick) a.onClick(); });
      acts.appendChild(b);
    });
    acts.hidden = !(actions && actions.length);
    var same = opts.owner != null && opts.owner === sheetOwner && !s.hidden;
    if (!same && sheetOnClose) { var prev = sheetOnClose; sheetOnClose = null; prev(); }
    sheetOwner = opts.owner || null;
    sheetOnClose = opts.onClose || null;
    if (s.hidden) s.hidden = false;
    if (!same) s.scrollTop = 0;
    document.documentElement.classList.add("ts-open");
  }
  function closeSheet() {
    if (!sheet || sheet.hidden) return;
    sheet.hidden = true;
    sheetOwner = null;
    if (sheetOnClose) { var cb = sheetOnClose; sheetOnClose = null; cb(); }
    document.documentElement.classList.remove("ts-open");
  }
  function sheetOpen() { return !!(sheet && !sheet.hidden); }
  // A tap outside the sheet and outside anything tip-able closes it.
  // Taps on another sheet-opening element swap the content instead; everything else closes it.
  // A mouse click outside always closes (touchscreen laptops switch input mid-session).
  document.addEventListener("pointerdown", function (e) {
    if (!sheetOpen() || sheet.contains(e.target)) return;
    if (e.pointerType !== "mouse" && e.target.closest && e.target.closest("[data-tipkit]")) return;
    closeSheet();
  }, true);
  // One layer per Escape: capture phase runs before page listeners, and an open sheet swallows the key.
  document.addEventListener("keydown", function (e) {
    if (e.key !== "Escape") return;
    if (sheetOpen()) { closeSheet(); hide(); e.stopPropagation(); return; }
    hide();
  }, true);
  window.addEventListener("scroll", hide, { passive: true });

  window.TipKit = { touchy: touchy, hover: hover, show: show, hide: hide,
    openSheet: openSheet, closeSheet: closeSheet, sheetOpen: sheetOpen };
})();
