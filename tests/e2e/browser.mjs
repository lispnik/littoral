// End-to-end checks of littoral.js in headless Chrome, over the DevTools
// protocol (Node 22+, no packages).  Expects the examples on $BASE:
//   make e2e
import { spawn } from "node:child_process";
const CHROME = process.env.CHROME || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const BASE = process.env.BASE || "http://127.0.0.1:8765";
// A fresh profile per run: no cached files or cookies from the last one.
const { mkdtempSync } = await import("node:fs");
const PROFILE = mkdtempSync("/tmp/littoral-e2e-");
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const chrome = spawn(CHROME, ["--headless=new", "--remote-debugging-port=9333",
  "--user-data-dir=" + PROFILE, "--no-first-run", "about:blank"], { stdio: "ignore" });
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

  // Report: sort, reverse, page.
  await go("/examples/report");
  const firstCell = () => evaluate(`document.querySelector(".lt-report tbody td").textContent`);
  check("report first page", await firstCell() === "1");
  await clickLink("Next");
  check("report next page", await firstCell() === "11");
  await clickLink("Name");
  check("report sorted by name", await firstCell() === "13");
  await clickLink("Name");
  check("report sort reversed", await firstCell() === "30");

  // Bookmarkable URLs: the address bar names the topic, and opening it fresh comes back.
  await go("/examples/topics");
  await clickLink("tasks");
  await clickLink("bigger");
  const href = await evaluate("location.pathname + location.search");
  check("topic in the URL", href.startsWith("/examples/topics/tasks?big&_s="), href);
  await send("Network.clearBrowserCookies");
  await go("/examples/topics/tasks?big");
  check("bookmark restores topic", (await evaluate("document.body.innerText")).includes("A flow of calls"));

  // File upload through a real multipart form.
  const { writeFileSync } = await import("node:fs");
  const upload = PROFILE + "/littoral-e2e-profile-upload.txt";
  writeFileSync(upload, "hello from chrome\n");
  await go("/examples/upload");
  const doc = await send("DOM.getDocument");
  const node = await send("DOM.querySelector", { nodeId: doc.result.root.nodeId, selector: "input[type=file]" });
  await send("DOM.setFileInputFiles", { files: [upload], nodeId: node.result.nodeId });
  await evaluate(`document.querySelector("button[type=submit]").click()`); await waitLoad();
  const text = await evaluate("document.body.innerText");
  check("upload received", text.includes("littoral-e2e-profile-upload.txt") && text.includes("hello from chrome"), text.slice(0, 200));

  // Chat: join, then send with a real Enter keypress; AJAX, no reload, focus kept.
  await go("/examples/chat");
  await clickLink("Join the room");
  await evaluate(`document.querySelector("input[type=text]").value = "e2e"`);
  await evaluate(`document.querySelector("button[type=submit]").click()`); await waitLoad();
  await evaluate("window.__chat = 1");
  await evaluate(`document.getElementById("draft").focus()`);
  await send("Input.insertText", { text: "hello room" });
  await send("Input.dispatchKeyEvent", { type: "keyDown", key: "Enter", code: "Enter", windowsVirtualKeyCode: 13, text: "\r" });
  await send("Input.dispatchKeyEvent", { type: "keyUp", key: "Enter", code: "Enter", windowsVirtualKeyCode: 13 });
  await sleep(600);
  check("chat message shown", (await evaluate(`document.querySelector(".chat-messages").innerText`)).includes("hello room"));
  check("chat did not reload", await evaluate("window.__chat") === 1);
  const active = await evaluate(`JSON.stringify({id: document.activeElement.id, value: document.activeElement.value, hasFocus: document.hasFocus()})`);
  check("chat input cleared and focused", JSON.parse(active).id === "draft" && JSON.parse(active).value === "", active);

  // Store: add to cart, then the whole checkout by clicking.
  await go("/examples/store");
  const addLinks = `[...document.querySelectorAll("a.add")]`;
  await evaluate(`${addLinks}[0].click()`); await waitLoad();
  await evaluate(`${addLinks}[1].click()`); await waitLoad();
  check("cart has two items", (await evaluate("document.body.innerText")).includes("2 items in your cart"));
  await clickLink("Checkout");
  const pressButton = async (label) => {
    await evaluate(`[...document.querySelectorAll("button")].find(b => b.textContent.includes(${JSON.stringify(label)})).click()`);
    await waitLoad();
  };
  await pressButton("Continue to delivery");
  for (const [id, v] of [["name", "Ada"], ["street", "1 Main St"], ["city", "Springfield"], ["postcode", "12345"]])
    await evaluate(`document.getElementById(${JSON.stringify(id)}).value = ${JSON.stringify(v)}`);
  await pressButton("Continue");
  await clickLink("›");
  await evaluate(`[...document.querySelectorAll(".date-picker-grid a")].find(a => a.textContent === "15").click()`); await waitLoad();
  await pressButton("OK");
  await pressButton("Yes");
  check("order placed", (await evaluate("document.body.innerText")).includes("Thank you! Order #"));
  await evaluate("history.back()"); await waitLoad(); await sleep(500); await waitLoad();
  const afterBack = await evaluate("location.search + ' | ' + document.body.innerText.slice(0, 300)");

  check("back after ordering cannot re-confirm", !afterBack.includes("Place an order"), afterBack);

  const errors = events.filter((e) => e.method === "Runtime.exceptionThrown");
  check("no JS exceptions", errors.length === 0, JSON.stringify(errors.map((e) => e.params.exceptionDetails.text)));
} catch (e) { console.log("ERROR " + e.message); failures++; }
finally {
  ws.close(); chrome.kill();
  await sleep(300);
  (await import("node:fs")).rmSync(PROFILE, { recursive: true, force: true });
}
process.exit(failures ? 1 : 0);
