// End-to-end checks of littoral.js in headless Chrome, over the DevTools
// protocol (Node 22+, no packages).  Expects the examples on $BASE:
//   make e2e
import { spawn } from "node:child_process";
const CHROME = process.env.CHROME || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const BASE = process.env.BASE || "http://127.0.0.1:8765";
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const chrome = spawn(CHROME, ["--headless=new", "--remote-debugging-port=9333",
  "--user-data-dir=" + (process.env.PROFILE || "/tmp/littoral-e2e-profile"), "--no-first-run", "about:blank"], { stdio: "ignore" });
let ws, id = 0; const pending = new Map(); const events = [];
for (let i = 0; i < 50; i++) {
  try { const r = await fetch("http://127.0.0.1:9333/json/list"); const t = (await r.json()).find((x) => x.type === "page");
        if (t) { ws = new WebSocket(t.webSocketDebuggerUrl); break; } } catch {}
  await sleep(200);
}
await new Promise((r) => ws.addEventListener("open", r));
ws.addEventListener("message", (m) => { const d = JSON.parse(m.data);
  if (d.id && pending.has(d.id)) { pending.get(d.id)(d); pending.delete(d.id); } else events.push(d); });
const send = (method, params = {}) => new Promise((r) => { const n = ++id; pending.set(n, r); ws.send(JSON.stringify({ id: n, method, params })); });
await send("Page.enable"); await send("Runtime.enable");
const evaluate = async (expr) => { const r = await send("Runtime.evaluate", { expression: expr, awaitPromise: true, returnByValue: true });
  if (r.result.exceptionDetails) throw new Error(JSON.stringify(r.result.exceptionDetails)); return r.result.result.value; };
const waitLoad = async () => { await sleep(300); for (let i = 0; i < 50; i++) { if (await evaluate("document.readyState") === "complete") return; await sleep(100); } };
const go = async (path) => { await send("Page.navigate", { url: BASE + path }); await waitLoad(); };
const clickLink = async (text) => { await evaluate(`[...document.querySelectorAll("a")].find(a => a.textContent.includes(${JSON.stringify(text)})).click()`); await waitLoad(); };
let failures = 0;
const check = (name, ok, detail = "") => { console.log((ok ? "PASS " : "FAIL ") + name + (ok ? "" : "  " + detail)); if (!ok) failures++; };

try {
  // AJAX counter: updates in place, no reload.
  await go("/examples/ajax");
  await evaluate("window.__marker = 42");
  const plus = `document.querySelector("[data-lt-on-click]").click()`;
  await evaluate(plus); await sleep(400); await evaluate(plus); await sleep(400);
  check("ajax counter updates", await evaluate(`document.querySelector(".ajax-count").textContent`) === "2");
  check("ajax did not reload page", await evaluate("window.__marker") === 42);
  // Handlers keep working on swapped-in HTML.
  await evaluate(`document.querySelectorAll("[data-lt-on-click]")[1].click()`); await sleep(400);
  check("swapped buttons still work", await evaluate(`document.querySelector(".ajax-count").textContent`) === "1");
  // Live echo on input.
  await evaluate(`(() => { const i = document.querySelector("[data-lt-on-input]"); i.value = "hi <there>"; i.dispatchEvent(new Event("input", {bubbles: true})); })()`);
  await sleep(500);
  check("on-input preview", (await evaluate(`document.querySelector("strong").textContent`)) === "hi <there>");
  // Periodical clock.
  const t1 = await evaluate(`document.querySelector("[data-lt-periodical]").textContent`);
  await sleep(2300);
  const t2 = await evaluate(`document.querySelector("[data-lt-periodical]").textContent`);
  check("periodical clock ticks", t1 !== t2, `${t1} -> ${t2}`);
  // State survives reload after AJAX.
  await send("Page.reload"); await waitLoad();
  check("ajax state persists across reload", await evaluate(`document.querySelector(".ajax-count").textContent`) === "1");

  // Back button on the plain counter.
  await go("/examples/counter");
  for (let i = 0; i < 3; i++) await clickLink("++");
  check("counter at 3", await evaluate(`document.querySelector("h1").textContent`) === "3");
  await evaluate("history.back()"); await waitLoad(); await evaluate("history.back()"); await waitLoad();
  check("back shows 1", await evaluate(`document.querySelector("h1").textContent`) === "1");
  await clickLink("++");
  check("++ from old page gives 2", await evaluate(`document.querySelector("h1").textContent`) === "2");

  // Halos.
  await go("/examples/multi-counter");
  await clickLink("Halos");
  check("halos shown", await evaluate(`document.querySelectorAll(".lt-halo").length`) === 6);
  await clickLink("inspect");
  check("inspector opens", (await evaluate("document.body.innerText")).includes("Inspector"));

  // Guess task through real form posts.
  await go("/examples/guess");
  await evaluate(`document.querySelector("button").click()`); await waitLoad();
  check("task asks for a guess", (await evaluate("document.body.innerText")).includes("Your guess?"));

  const errors = events.filter((e) => e.method === "Runtime.exceptionThrown");
  check("no JS exceptions", errors.length === 0, JSON.stringify(errors.map((e) => e.params.exceptionDetails.text)));
} catch (e) { console.log("ERROR " + e.message); failures++; }
finally { ws.close(); chrome.kill(); }
process.exit(failures ? 1 : 0);
