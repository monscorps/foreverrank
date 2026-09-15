/* The Forge character viewer: one WebGL stage that survives re-renders.
 * Models are GLB files converted from the WoW client (see models/manifest.json).
 * Loaded on demand by plan.js; three.js r186 is bundled in vendor/three-forge.min.js. */
import {
  WebGLRenderer, Scene, PerspectiveCamera, HemisphereLight, DirectionalLight, AnimationMixer, Box3, Vector3,
  LoopOnce, LoopRepeat, SRGBColorSpace, Mesh, CircleGeometry, MeshBasicMaterial, CanvasTexture, Clock,
  GLTFLoader, OrbitControls
} from "./vendor/three-forge.min.js";

const LOOPING = { Stand: 1, Walk: 1, Run: 1, Dance: 1, SitGround: 1, ReadySpell: 1 };

export function create(opts) {
  const base = opts.base || "models/";
  const wrap = document.createElement("div");
  wrap.className = "fm3d";
  wrap.innerHTML = '<div class="fm3d-msg" hidden></div>';
  const msg = wrap.firstChild;

  let renderer;
  try {
    renderer = new WebGLRenderer({ antialias: true, alpha: true, powerPreference: "low-power" });
  } catch (e) {
    return null;
  }
  renderer.outputColorSpace = SRGBColorSpace;
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
  wrap.insertBefore(renderer.domElement, msg);

  const scene = new Scene();
  const camera = new PerspectiveCamera(28, 1, 0.01, 100);
  scene.add(new HemisphereLight(0xfff4e0, 0x2a3440, 1.7));
  const key = new DirectionalLight(0xffffff, 2.1);
  key.position.set(-1.5, 2.5, 3);
  scene.add(key);
  const rim = new DirectionalLight(0x9fd3ff, 0.9);
  rim.position.set(2, 1.5, -2.5);
  scene.add(rim);

  // Soft floor glow under the feet.
  const gc = document.createElement("canvas");
  gc.width = gc.height = 128;
  const g2 = gc.getContext("2d");
  const grad = g2.createRadialGradient(64, 64, 4, 64, 64, 62);
  grad.addColorStop(0, "rgba(229,204,128,0.38)");
  grad.addColorStop(0.55, "rgba(0,175,215,0.12)");
  grad.addColorStop(1, "rgba(0,0,0,0)");
  g2.fillStyle = grad;
  g2.fillRect(0, 0, 128, 128);
  const floor = new Mesh(new CircleGeometry(1, 48), new MeshBasicMaterial({ map: new CanvasTexture(gc), transparent: true, depthWrite: false }));
  floor.rotation.x = -Math.PI / 2;
  scene.add(floor);

  const controls = new OrbitControls(camera, renderer.domElement);
  controls.enablePan = false;
  controls.enableZoom = false;
  controls.enableDamping = true;
  controls.dampingFactor = 0.12;
  controls.rotateSpeed = 0.8;
  controls.minPolarAngle = 1.05;
  controls.maxPolarAngle = 1.75;
  // Let vertical swipes scroll the page on phones; horizontal drags spin the model.
  renderer.domElement.style.touchAction = "pan-y";

  const loader = new GLTFLoader();
  const cache = new Map();
  const load = (url) => {
    if (!cache.has(url)) {
      const p = new Promise((res, rej) => loader.load(url, res, undefined, rej));
      p.catch(() => cache.delete(url)); // a dropped request can be retried later
      cache.set(url, p);
    }
    return cache.get(url);
  };

  let manifest = null, manifestP = null;
  function manifestReady() {
    if (manifest) return Promise.resolve(manifest);
    if (!manifestP) {
      manifestP = fetch(base + "manifest.json", { cache: "no-store" })
        .then((r) => { if (!r.ok) throw new Error("manifest " + r.status); return r.json(); })
        .then((m) => (manifest = m))
        .catch(() => { manifestP = null; return null; });
    }
    return manifestP;
  }

  const clock = new Clock();
  let cur = null; // { key, root, mixer, actions, height, playing }
  let wantKey = null, visible = true, closeUp = false, loops = 0;

  function say(text) {
    msg.textContent = text || "";
    msg.hidden = !text;
  }

  function frame(height, center) {
    const h = height * (closeUp ? 0.3 : 1);
    const cy = closeUp ? center.y + height * 0.36 : center.y;
    const dist = (h * 0.62) / Math.tan((camera.fov * Math.PI) / 360) + height * 0.15;
    const dir = camera.position.clone().sub(controls.target);
    if (dir.lengthSq() < 1e-6) dir.set(0.25, 0.05, 1);
    dir.normalize().multiplyScalar(dist);
    controls.target.set(center.x, cy, center.z);
    camera.position.copy(controls.target).add(dir);
    camera.near = dist / 50;
    camera.far = dist * 20;
    camera.updateProjectionMatrix();
    controls.update();
  }

  function fade(to, name) {
    if (!cur) return;
    const from = cur.playing;
    if (from === to) return;
    to.reset().setEffectiveWeight(1).play();
    if (from) to.crossFadeFrom(from, 0.35, false);
    cur.playing = to;
    cur.name = name;
  }

  function standClip() {
    const a = cur.actions;
    loops++;
    const vars = Object.keys(a).filter((n) => /^Stand_v\d+$/.test(n));
    if (vars.length && loops > 3 && Math.random() < 0.35) {
      loops = 0;
      const n = vars[Math.floor(Math.random() * vars.length)];
      a[n].setLoop(LoopOnce, 1);
      a[n].clampWhenFinished = true;
      return [a[n], n];
    }
    return [a.Stand, "Stand"];
  }

  async function show(k) {
    wantKey = k;
    if (cur && cur.key === k) return;
    await manifestReady();
    if (wantKey !== k) return;
    const entry = manifest && manifest.models && manifest.models[k];
    if (!entry) {
      if (cur) { scene.remove(cur.root); cur = null; }
      say("");
      wrap.dispatchEvent(new CustomEvent("fm3d:model", { bubbles: true, detail: { key: k, missing: true, clips: [] } }));
      return;
    }
    say("Loading model...");
    wrap.classList.add("loading");
    let gltf;
    try {
      gltf = await load(base + entry.file);
    } catch (e) {
      if (wantKey === k) { say("The model could not load."); wrap.classList.remove("loading"); }
      return;
    }
    if (wantKey !== k) return;
    if (cur) scene.remove(cur.root);
    const root = gltf.scene;
    // Geosets are optional body parts (sleeves, boots, robe, cape); the converter marks the default look.
    const box = new Box3(), v = new Vector3();
    root.updateMatrixWorld(true);
    root.traverse((o) => {
      if (o.userData && o.userData.geosetId !== undefined) o.visible = !!o.userData.defaultVisible;
    });
    root.traverse((o) => {
      if (!o.isMesh || !o.visible) return;
      let p = o.parent, shown = true;
      while (p) { if (!p.visible) { shown = false; break; } p = p.parent; }
      if (!shown) return;
      const pos = o.geometry.attributes.position, idx = o.geometry.index;
      const n = idx ? idx.count : pos.count;
      for (let i = 0; i < n; i++) box.expandByPoint(v.fromBufferAttribute(pos, idx ? idx.getX(i) : i).applyMatrix4(o.matrixWorld));
    });
    if (box.isEmpty()) box.setFromObject(root);
    const mixer = new AnimationMixer(root);
    const actions = {};
    gltf.animations.forEach((clip) => { actions[clip.name] = mixer.clipAction(clip); });
    const size = box.getSize(new Vector3()), center = box.getCenter(new Vector3());
    floor.position.set(center.x, box.min.y + 0.002, center.z);
    floor.scale.setScalar(Math.max(size.x, size.z, size.y * 0.35) * 0.9);
    scene.add(root);
    cur = { key: k, root, mixer, actions, height: size.y, center, playing: null, name: "", anims: entry.anims || null, packs: null };
    mixer.addEventListener("finished", (e) => {
      if (!cur || cur.mixer !== mixer || e.action !== cur.playing) return;
      const s = standClip();
      fade(s[0], s[1]);
      clipEvent();
    });
    mixer.addEventListener("loop", (e) => {
      if (!cur || cur.mixer !== mixer || cur.name !== "Stand" || e.action !== actions.Stand) return;
      const s = standClip();
      if (s[1] !== "Stand") fade(s[0], s[1]);
    });
    if (actions.Stand) fade(actions.Stand, "Stand");
    frame(size.y, center);
    say("");
    wrap.classList.remove("loading");
    wrap.dispatchEvent(new CustomEvent("fm3d:model", { bubbles: true, detail: { key: k, missing: false, clips: clipsFor(k), standIn: !!entry.standIn, note: entry.note || "" } }));
  }

  function clipEvent() {
    if (cur) wrap.dispatchEvent(new CustomEvent("fm3d:clip", { bubbles: true, detail: { clip: cur.name, clips: clipsFor(cur.key) } }));
  }

  function clipsFor(k) {
    const e = manifest && manifest.models && manifest.models[k];
    return ["Stand"].concat(e && e.anims && e.anims.clips ? e.anims.clips : []);
  }

  async function play(name) {
    if (!cur) return false;
    const c = cur;
    if (name === "Stand") { loops = 0; fade(c.actions.Stand, "Stand"); clipEvent(); return true; }
    if (!c.actions[name] && c.anims) {
      if (!c.packs) {
        c.packs = load(base + c.anims.file).then((g) => {
          g.animations.forEach((clip) => { if (!c.actions[clip.name]) c.actions[clip.name] = c.mixer.clipAction(clip); });
        }).catch(() => { c.packs = null; });
      }
      wrap.classList.add("loading");
      await c.packs;
      wrap.classList.remove("loading");
    }
    if (cur !== c || !c.actions[name]) return false;
    const a = c.actions[name];
    if (LOOPING[name]) a.setLoop(LoopRepeat, Infinity);
    else { a.setLoop(LoopOnce, 1); a.clampWhenFinished = true; }
    fade(a, name);
    clipEvent();
    return true;
  }

  function toggleClose() {
    closeUp = !closeUp;
    if (cur) frame(cur.height, cur.center);
    wrap.dispatchEvent(new CustomEvent("fm3d:zoom", { bubbles: true, detail: { on: closeUp } }));
    return closeUp;
  }

  function resize() {
    const w = wrap.clientWidth, h = wrap.clientHeight;
    if (!w || !h) return;
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
  }
  const ro = typeof ResizeObserver !== "undefined" ? new ResizeObserver(resize) : null;
  if (ro) ro.observe(wrap);
  const io = typeof IntersectionObserver !== "undefined" ? new IntersectionObserver((en) => { visible = en[0].isIntersecting; }) : null;
  if (io) io.observe(wrap);
  renderer.domElement.addEventListener("dblclick", toggleClose);
  (function watchDpr() {
    if (!window.matchMedia) return;
    const mq = matchMedia("(resolution: " + (window.devicePixelRatio || 1) + "dppx)");
    if (mq.addEventListener) mq.addEventListener("change", () => { resize(); watchDpr(); }, { once: true });
  })();

  renderer.setAnimationLoop(() => {
    const dt = Math.min(clock.getDelta(), 0.1);
    if (!visible || document.hidden || !wrap.isConnected) return;
    if (cur) cur.mixer.update(dt);
    controls.update();
    renderer.render(scene, camera);
  });

  return {
    el: wrap,
    attach(host) {
      if (wrap.parentNode !== host) host.appendChild(wrap);
      resize();
    },
    show, play, toggleClose,
    has: (k) => !!(manifest && manifest.models && manifest.models[k]),
    ready: manifestReady,
    isCloseUp: () => closeUp,
    current: () => (cur ? { key: cur.key, clip: cur.name, clips: clipsFor(cur.key) } : null),
  };
}
