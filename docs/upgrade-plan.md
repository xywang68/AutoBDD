
---

## 0. Phase 0 Spike — results (2026-09-01)

Branches created in all four repos: `phase-0` in **AutoBDD, AutoBDD-example, autobdd-test,
xySikulixApi**. (Oculix is a third-party upstream repo — not branched; consumed as a built
jar / submodule reference.)

### Verified outcomes

1. **Oculix jar obtained & built.** Maven Central `io.github.oculix-org:oculixapi` thin
   jar (9.4 MB) lacks bundled native deps (OpenCV missing) — **must use the fat jar** built
   via `mvn -pl API -am -Pcomplete-lux-jar`: `API/target/oculixapi-4.0.0-complete-lux.jar`
   (137 MB), which bundles OpenCV + Tesseract (Legerix) natives + tessdata. Built with
   `maven:3.9-eclipse-temurin-17` in Docker. Oculix needs Java 17.

2. **`java` (node-java) is confirmed dead on Node 20+** — failed to build (node-gyp JNI).
   The MarkusJx **`java-bridge`** package (Rust/napi-rs, v2.8.1, prebuilt
   `java.linux-x64-gnu.node`) is the working replacement. Note: a *different* npm package
   `node-java-bridge` (v1.0.22) merely wraps the old `java` — avoid it.

3. **OCR verified end-to-end** through `java-bridge` + Oculix fat jar: PIL-generated image
   with text → `Image.create` + `OCR.readText` → returned `"Hello World AutoBDD …"`.

4. **Template find verified end-to-end:** `new Finder(imagePath)` + `Pattern.similarSync`
   + `find` → found the DOWNLOAD button at exactly (100,100), score 0.9999.

5. **Oculix input classes available** (`Mouse` static: `move/click/down/up/type/wheel`,
   `Key` constants) — keyboard/mouse can be routed through Oculix, **dropping robotjs**.
   `Mouse.moveSync` blocked on a bare Xvfb without a window manager (expected — needs the
   desktop session present in the container).

6. **robotjs actually still works on Node 22** — installed cleanly, `getScreenSize()`
   returns a valid size, `moveMouse` present. So robotjs is *not* a hard blocker, but it is
   still unmaintained. **Decision: migrate keyboard/mouse to Oculix** (single JVM, removes
   the native dep) rather than keep robotjs; robotjs remains a documented fallback.

7. **Ubuntu 22.04 package set:** all 59 packages in `autobdd-ubuntu.dockerfile` (incl.
   `rdesktop`, `ttf-wqy-zenhei`, `libpng++-dev`, `aosd-cat`) are available in jammy.

8. **java-bridge API is compatible with the existing xysikulixapi code style:**
   `classpath.append(jar)` + `importClass('org.sikuli.script.Screen')` + `*Sync()` /
   `*Async()` methods mirror the `java.classpath.push` + `java.import` + `*Sync()` pattern.
   The xySikulixApi migration is a dependency swap, not a rewrite.

### Decisions locked in for later phases
- **Screen bridge = xysikulixapi repointed at the Oculix fat jar**, with `java` → `java-bridge`.
- **Keyboard/mouse = Oculix Mouse/Key** (drop robotjs).
- **Ubuntu 22.04** base (all packages present; avoids 24.04 rdesktop issue).
- **Oculix fat jar is built upstream** (Oculix repo) — AutoBDD consumes it, does not build it.

### Open items carried into Phase 1
- Wire Oculix fat-jar download/build into the AutoBDD image build (or xysikulixapi
  postinstall), and install `xdotool` in the container (needed by App window ops and
  Mouse input on the live desktop).

**Goal:** Bring AutoBDD, autobdd-test, and AutoBDD-example back to a working state on a
modern stack; upgrade every library and internal component (WebdriverIO, Docker/Ubuntu,
Node.js, SikuliX→Oculix, Python, Selenium, reporting). The "worked 6 years ago with its
example + test projects" claim is unverified and must be re-established end-to-end.

**Author:** xyteam-assistant · **Date:** 2026-09-01

---

## 1. Verified current state (research findings)

### Architecture at a glance

```
AutoBDD (npm package, v3.0.0)                    ← main framework
├── framework/libs/screen_session.js             ← screen/image/keyboard-mouse
│     └── execSync('findTargetImage …')          ← CLI bridge → xysikulixapi
├── framework/scripts/old-findTargetImage.js     ← orphaned (renamed "old-" 2021)
├── framework/scripts/getImageText.js            ← tesseract OCR (native)
├── framework/configs/abdd_*.js                  ← wdio 7 sync configs (selenium grid)
├── framework/support/{hooks,env,abdd}.js        ← wdio 7 hooks, cucumber ≤6 style
├── framework/step_files/**                      ← ~34 step files (sync browser.*)
└── .docker/*.dockerfile                         ← ubuntu:20.04 → node 14 → autobdd
autobdd-test / AutoBDD-example                   ← separate repos, pull xyteam/autobdd image
```

### Key findings (evidence-based)

1. **`findTargetImage` binary comes from the `xysikulixapi` npm package**, not from
   AutoBDD itself. `screen_session.js` calls `execSync('findTargetImage …')`; the local
   `old-findTargetImage.js` was renamed `old-` in commit 628cd78 (2021-07) and is orphaned
   — a candidate for deletion, replaced by the npm CLI.

2. **The SikuliX bridge is `xysikulixapi` (npm `^0.0.11`, source now at
   `../xySikulixApi`, local v0.0.12).** It:
   - downloads `sikulixapi-2.0.4.jar` (from launchpad.net) at postinstall;
   - loads it into a JVM via the **`java` npm package (joeferner/node-java)**;
   - imports `org.sikuli.script.{App,Button,ImagePath,Mouse,OCR,Pattern,Region,Settings,Screen}`;
   - provides the `findTargetImage` CLI that does find/OCR/click/type on a screen region.
   - **`java` (node-java) is unmaintained and fails to build on Node ≥20**
     (JNI, node-gyp; issue #588 "Not able to install node java in node 20"). This is the
     **single highest-risk blocker** for the whole upgrade.

3. **Oculix (../Oculix, v4.0.0) is the SikuliX1 successor.** It is Maven
   `io.github.oculix-org:oculixapi:4.0.0`, **preserves the `org.sikuli.script.*` package
   namespace** (Screen, Region, Pattern, Match, OCR, App, Button, Mouse…). Native OpenCV +
   Tesseract bundled. Because the namespace is unchanged, `xysikulixapi`'s import list can
   be **repointed at Oculix's jar** with minimal code change — this is the natural
   SikuliX→Oculix cutover. Oculix needs Java 11+ (no newer JVM constraints).

4. **robotjs** (`screen_session.js`, keyboard/mouse) is unmaintained; known build risk on
   Node ≥18. AutoBDD calls it only for keyboard/mouse primitives. Candidate replacement:
   `@nut-tree/nut-js`, or route input through the same Oculix JVM (Oculix has Mouse/Keyboard
   classes).

5. **wdio is v7.7.7 (sync mode)**; `@wdio/sync` removed in v8; wdio is now at **9.30.x**.
   Sync→async is the dominant migration (every `browser.*`, `$`, `expect`, step def, hook).

6. **Docker stack is EOL:** ubuntu:20.04 (EOL 2025-05), Node 14 (EOL), Python 3.8,
   Selenium 3.141.59, deprecated `apt-key`. Google Chrome apt repo uses deprecated `apt-key
   add/adv`. Current host has Docker 29.5.3 + Compose v5.3.1, Node v22.22.2 (host).

7. **`findTargetImage` CLI is not found by name** anywhere as a file — it resolves only
   through node_modules/.bin (via `.autoPathrc.sh` PATH). The old AutoBDD script was
   orphaned. This is one concrete broken link to fix.

8. **`abdd.js` / `abdd_*.js` configs use `cucumberOpts.tagExpression`** (cucumber ≤6).
   wdio v9 bundles cucumber v10+ (`tags`, changed hook signatures, `this.Then` removed).

9. **autobdd-test and AutoBDD-example** are separate repos consuming the
   `xyteam/autobdd:${AutoBDD_Ver}` image (both pin `AutoBDD_Ver=2.3.0`; AutoBDD is v3.0.0 —
   already a mismatch). They contain legacy `this.Then(...)` step files.

---

## 2. Target stack

| Component | Current | Target | Notes |
|---|---|---|---|
| WebdriverIO | 7.7.7 (sync) | 9.30.x (async) | dominant migration effort |
| Node.js (Docker) | 14 (EOL) | 20 LTS (or 22 LTS) | wdio v9 needs ≥18.20/≥20.9 |
| Ubuntu base | 20.04 (EOL) | 22.04 LTS | rdesktop dropped in 24.04; prefer 22.04 unless 24.04 verified |
| Python | 3.8 | 3.10+ (3.12) | autorunner.py already py3-clean |
| Selenium | 3.141.59 | 4.x + current drivers | selenium-standalone service |
| SikuliX bridge | xysikulixapi → sikulixapi-2.0.4.jar (via node-java) | xysikulixapi → **oculixapi-4.0.0.jar** (via node-java-bridge) | namespace preserved |
| Java bridge | `java` (node-java, broken) | `node-java-bridge` (Rust/napi, prebuilt) | resolves the top blocker |
| Keyboard/mouse | robotjs (unmaintained) | Oculix Mouse/Keyboard via JVM, or @nut-tree | spike needed |
| Chrome | 91 (pinned chromedriver) | current Chrome + chromedriver | Selenium 4 manager handles |
| Cucumber | v6 (tagExpression, this.Then) | v10+ (tags, async hooks) | bundled with wdio v9 |
| Docker compose | `version:` key + `--compress` | compose v2 (drop obsolete flags) | |

---

## 3. Phased implementation plan

Each phase is independently verifiable. Gates after phases 1, 3, 5.

### Phase 0 — Spike (highest risk, do first)

Build the Docker image with the new stack and verify the two riskiest native pieces:

- **0.1** Node 20/22 + `node-java-bridge` + Oculix jar: verify `org.sikuli.script.Screen`
  importable from Node and a sample `find`/OCR works inside the container.
  - Outcome: either (a) node-java-bridge works with Oculix jar → adopt; or (b) need
    alternate bridge (spawn JVM + JSON-RPC, e.g. the `operix-js`/`oculix` java-caller
    approach documented in Oculix/Additional-Wrappers). Decide here, not later.
- **0.2** robotjs on Node 20: try node-gyp rebuild; if it fails, migrate keyboard/mouse to
  Oculix Mouse/Keyboard (preferred — removes a native dep) and drop robotjs.
- **0.3** Ubuntu 22.04 package check: `aosd-cat`, `libpng++-dev`, `libopencv-dev`,
  `ttf-wqy-zenhei`, `rdesktop`/`freerdp`, tesseract-ocr.

**Gate 1:** a minimal container boots, `npm install` succeeds, a bare Chrome session
launches, and an Oculix `find` on a sample image returns a match.

### Phase 1 — Docker foundation

- **1.1** `autobdd-ubuntu.dockerfile`: ubuntu 22.04; replace `apt-key add/adv` with
  `gpg --dearmor`; drop python2 support file (`enable_python2_support.sh` removed);
  bump Python.
- **1.2** `autobdd-nodejs.dockerfile`: Node 20 LTS (nodesource `setup_20.x`); delete the
  obsolete "16.x breaks fiber" comment (fiber was only for wdio sync). Refresh google-
  chrome / k6 / terraform / hashicorp apt keys via gpg-dearmor.
- **1.3** `autobdd-image.dockerfile` + `autobdd.root/`: install requirements, `npm
  install`, wire the Oculix jar download into the build (or into xysikulixapi postinstall).
- **1.4** `docker-compose.yml` (AutoBDD + example + test): drop `version:` key; `.docker/
  Makefile`: drop `--compress`.
- **1.5** Bump `AUTOBDD_VERSION`/`AutoBDD_Ver` consistently to a new release version.

**Gate 2:** `make autobdd-build-all` succeeds; `autobdd-bash` opens a shell; python
dry-run passes.

### Phase 2 — Screen bridge: SikuliX → Oculix (xySikulixApi)

- **2.1** In `../xySikulixApi` (now cloned locally):
  - swap `java` → `node-java-bridge` (same `java.import`/`java.classpath` surface);
  - download Oculix `oculixapi-4.0.0.jar` instead of `sikulixapi-2.0.4.jar`
    (`downloadSikulixApiJar.js`: URL → Maven Central);
  - confirm all `org.sikuli.script.*` imports still resolve against Oculix.
- **2.2** Publish/bump `xysikulixapi` to a new version (e.g. 0.1.0) pointing at Oculix.
- **2.3** AutoBDD `package.json`: bump `xysikulixapi`; remove `java` dep (now inside the
  bridge). Keep `fuzzball` (used by screen/then.js).
- **2.4** Decide robotjs fate per 0.2; if migrating input to Oculix, update
  `screen_session.js` keyboard/mouse functions accordingly.
- **2.5** Delete orphaned `framework/scripts/old-findTargetImage.js` and its only deps
  (`java`, `xysikulixapi` in AutoBDD package.json if not elsewhere used).
- **2.6** Verify `getImageText.js` (tesseract OCR) against the new image; keep or fold
  into Oculix OCR.

**Gate 3:** `findTargetImage` and screen image-finding work end-to-end against Oculix on
the new image (both real display and xvfb).

### Phase 3 — Dependency hygiene (isolate variables before the wdio bump)

- **3.1** Remove Node built-ins as deps: `child_process`, `path`, `assert`.
- **3.2** Remove/verify dead deps: `@hapi/hapi`, `hoek`, `cryptiles`, `moment` (or →dayjs),
  `java`+`xysikulixapi` (per 2.5), `request` (→ global `fetch`), `url-parse` if only
  transitive, `newman` → ^6, `npm-check-updates` → latest, `allure-commandline` → latest.
- **3.3** `xlsx` ^0.17.0 (known CVEs) → ^0.18.5 or `exceljs` (used in `libs/fs_session.js`).
- **3.4** `fs-ext` (`safexvfb.js` flockSync) → pure-JS `proper-lockfile` (drop native dep).
- **3.5** Run full test suite on **wdio v7 still** to confirm hygiene didn't break the
  pre-upgrade behavior.

**Gate 4:** `npm install` clean, existing (pre-upgrade) tests still pass on wdio v7.

### Phase 4 — WebdriverIO v7 → v9 (dominant effort)

- **4.1** Sync → async: `await` every `browser.*`, `$()`, `$$()`, `expect()`; make every
  step def + hook `async`. Files: `framework/step_functions/**`,
  `framework/step_files/{browser,screen,shell,vcenter,nodejs,postman,maven}/**`,
  `framework/libs/{browser_session,fs_session,framework_libs,vcenter_session}.js`,
  `framework/support/hooks.js`.
- **4.2** Command renames: `windowHandleMaximize`→`maximizeWindow`;
  `getWindowHandle().on('DOMContentLoaded')`→`browser.execute(readyState)`/`waitUntil`;
  `waitForExist`→`waitForExists` (v9).
- **4.3** Cucumber: `cucumberOpts.tagExpression`→`tags` in all configs; update hook
  signatures; rewrite legacy `this.Then`→`const {Then}=require('@cucumber/cucumber')`.
- **4.4** Dep bumps (root devDeps): `@wdio/*`→^9.30, remove `@wdio/sync`,
  `@wdio/jasmine-framework`, `@rpii/wdio-html-reporter`, `wdio-chromedriver-service`,
  `devtools`+`automationProtocol`; add `@wdio/globals`; bump `expect-webdriverio`→^6,
  `wdio-cucumberjs-json-reporter`→^6.
- **4.5** Configs: `abdd_Linux_CH.js`, `abdd_Linux_FF.js`, `abdd_Win10_*.js` — reporter
  blocks to cucumberjs-json v6 names; selenium-standalone service to Selenium 4; confirm
  `abdd_local.js` (legacy Chimp) dead → remove.

**Gate 5:** one feature runs end-to-end against a real browser via `abdd_Linux_CH.js`.

### Phase 5 — Reporting pipeline

- **5.1** `wdio-cucumberjs-json-reporter` v6 config keys; `multiple-cucumber-html-reporter`
  v3 (or replacement) parsing cucumber v10/wdio v9 JSON.
- **5.2** Re-verify `scripts/{gen-report,generate-reports,testrail-reports}.js`,
  `parseARunnerLog.js`, `autorunner.py` (tagExpression→tags translation).
- **5.3** Python tooling: bump per Phase 1; smoke autorunner dry-run + parallel run.

**Gate 6:** full HTML report with step screenshots + movie generated from a real run.

### Phase 6 — Test-project cutover (two repos)

- **6.1** autobdd-test: bump package.json to wdio v9; rewrite legacy `this.Then` steps;
  update `Makefile`/`docker-compose.yml` to new image tag + compose v2; verify each test
  family (`e2e-test`, `js-test` jest, `cy-test` cypress, `py3-test`, `k6-test`).
- **6.2** AutoBDD-example: same; verify `@Demo` tag run end-to-end; confirm report output.
- **6.3** Coordinated release: bump framework + both test repos; cut over the degit URL/tag
  in AutoBDD `package.json` `download-test` script (currently `#v3master`).

**Gate 7:** both projects' smoke runs pass on the new image.

### Phase 7 — Obsolete platform cleanup

- **7.1** Drop IE (`abdd_Win10_IE.js`, IE driver) — IE EOL 2022.
- **7.2** Edge via msedgedriver (replace 2015-era `MicrosoftWebDriver.exe`).
- **7.3** Remove `abdd_local.js` (legacy Chimp config) if confirmed dead.
- **7.4** Remove dead/legacy scripts and docs; update READMEs; bump versions; tag release.

---

## 4. Cross-cutting decisions & risks

| # | Decision / risk | Mitigation |
|---|---|---|
| D1 | **`java` (node-java) is broken on Node 20** — top blocker | Phase 0 spike: `node-java-bridge` (prebuilt Rust/napi, same API) first; fallback: spawn JVM + JSON-RPC (operix-js model) |
| D2 | **Oculix vs SikuliX jar** — Oculix keeps `org.sikuli.script.*` | Repoint xysikulixapi at oculixapi-4.0.0.jar; verify each import resolves |
| D3 | **robotjs** unmaintained, won't build on Node 20 | Prefer Oculix Mouse/Keyboard (removes dep); else `@nut-tree/nut-js`; decided in 0.2 |
| D4 | **Ubuntu 22.04 vs 24.04** | Default 22.04 (rdesktop present); only go 24.04 if 22.04 package set fails |
| D5 | **wdio v9 sync→async is large** | Sequence: hygiene on v7 first (Phase 3), then one wdio bump with a canary feature per browser |
| D6 | **wdio v9 JSON vs old reporters** | Spike reporter parsing in Phase 5; swap `multiple-cucumber-html-reporter` if it can't read v9 JSON |
| D7 | **"worked 6 years ago" unverified** | No assumption; every phase's gate re-proves behavior end-to-end from a clean container |

---

## 5. Definition of done

- `make autobdd-build-all` builds a modern image (Ubuntu 22.04, Node 20, Python 3.10+,
  Selenium 4, Oculix-based screen bridge).
- `make autobdd-test` (or the test-project equivalent) runs **all** test families green:
  e2e (browser + screen/image + shell + nodejs + maven + postman + vcenter), jest, cypress,
  py3, k6.
- AutoBDD-example `@Demo` run produces a valid searchable HTML report with screenshots and
  movie.
- All libraries and internal components upgraded to the latest compatible versions; dead
  code (IE, Chimp config, orphaned `old-findTargetImage.js`, obsolete deps) removed.
- Both test projects consume the new framework version via a coordinated release.
