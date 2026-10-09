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
// Chrome can take a while to start on a busy CI machine.
for (let i = 0; i < 300 && !ws; i++) {
  try { const r = await fetch("http://127.0.0.1:9333/json/list"); const t = (await r.json()).find((x) => x.type === "page");
        if (t) { ws = new WebSocket(t.webSocketDebuggerUrl); break; } } catch {}
  await sleep(200);
}
if (!ws) { console.log("ERROR Chrome did not start within 60 seconds"); chrome.kill(); process.exit(1); }
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
// A second tab with its own DevTools connection (a separate session).
async function openTab() {
  const t = await (await fetch("http://127.0.0.1:9333/json/new?about:blank", { method: "PUT" })).json();
  const sock = new WebSocket(t.webSocketDebuggerUrl);
  await new Promise((r) => sock.addEventListener("open", r));
  let n = 0; const waiting = new Map();
  sock.addEventListener("message", (m) => { const d = JSON.parse(m.data);
    if (d.id && waiting.has(d.id)) { waiting.get(d.id)(d); waiting.delete(d.id); } });
  const tsend = (method, params = {}) => new Promise((r) => { const k = ++n; waiting.set(k, r); sock.send(JSON.stringify({ id: k, method, params })); });
  await tsend("Page.enable"); await tsend("Runtime.enable");
  const teval = async (expr) => { const r = await tsend("Runtime.evaluate", { expression: expr, awaitPromise: true, returnByValue: true });
    if (r.result.exceptionDetails) throw new Error(JSON.stringify(r.result.exceptionDetails)); return r.result.result.value; };
  const tload = async () => { await sleep(300); for (let i = 0; i < 50; i++) { if (await teval("document.readyState") === "complete") return; await sleep(100); } };
  return {
    evaluate: teval, waitLoad: tload,
    go: async (path) => { await tsend("Page.navigate", { url: BASE + path }); await tload(); },
    clickLink: async (text) => { await teval(`[...document.querySelectorAll("a")].find(a => a.textContent.includes(${JSON.stringify(text)})).click()`); await tload(); },
    close: () => fetch("http://127.0.0.1:9333/json/close/" + t.id),
  };
}

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
  // Values from the browser, results back, confirm and server scripts.
  await evaluate(`document.getElementById("measure").click()`); await sleep(500);
  check("browser value reaches server and result comes back",
        /The server heard \d+x\d+\./.test(await evaluate(`document.getElementById("reply").textContent`)));
  await evaluate("window.confirm = () => false");
  await evaluate(`document.getElementById("reset").click()`); await sleep(500);
  check("declined confirm sends nothing", await evaluate(`document.querySelector(".ajax-count").textContent`) === "1");
  await evaluate("window.confirm = () => true");
  await evaluate(`document.getElementById("reset").click()`); await sleep(500);
  check("accepted confirm runs", await evaluate(`document.querySelector(".ajax-count").textContent`) === "0");
  await evaluate(`document.getElementById("retitle").click()`); await sleep(500);
  check("server script ran", await evaluate("document.title") === "Counter at 0");
  // Leave the counter where the reload check below expects it.
  await evaluate(`document.querySelector("[data-lt-on-click]").click()`); await sleep(400);

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

  // Members: sign in through DemoID, the whole OAuth flow in a real browser.
  await go("/examples/members");
  await clickLink("Sign in");
  await evaluate(`[...document.querySelectorAll("button")].find(b => b.textContent.includes("Sign in with DemoID")).click()`);
  await waitLoad();
  check("demoid asks", (await evaluate("location.pathname")) === "/examples/demo-idp");
  await evaluate(`[...document.querySelectorAll("button")].find(b => b.textContent.includes("carol@example.org")).click()`);
  await waitLoad();
  check("signed in through demoid", (await evaluate("document.body.innerText")).includes("Signed in as carol"));

  // Chat: join, then send with a real Enter keypress; AJAX, no reload, focus kept.
  await go("/examples/chat");
  await clickLink("Join the room");
  await evaluate(`document.querySelector("input[type=text]").value = "e2e"`);
  await evaluate(`document.querySelector("button[type=submit]").click()`); await waitLoad();
  await evaluate("window.__chat = 1");
  // On Hunchentoot the chat talks over a WebSocket; Woo serves push from its
  // event loops and keeps server-sent events.
  if (process.env.LITTORAL_SERVER !== "woo") {
    await sleep(500);
    check("chat uses a websocket", await evaluate("window.littoral.transport()") === "websocket");
  }
  await evaluate(`document.getElementById("draft").focus()`);
  await send("Input.insertText", { text: "hello room" });
  await send("Input.dispatchKeyEvent", { type: "keyDown", key: "Enter", code: "Enter", windowsVirtualKeyCode: 13, text: "\r" });
  await send("Input.dispatchKeyEvent", { type: "keyUp", key: "Enter", code: "Enter", windowsVirtualKeyCode: 13 });
  await sleep(600);
  check("chat message shown", (await evaluate(`document.querySelector(".chat-messages").innerText`)).includes("hello room"));
  check("chat did not reload", await evaluate("window.__chat") === 1);
  const active = await evaluate(`JSON.stringify({id: document.activeElement.id, value: document.activeElement.value, hasFocus: document.hasFocus()})`);
  check("chat input cleared and focused", JSON.parse(active).id === "draft" && JSON.parse(active).value === "", active);

  // Server push: a second session's message appears without polling or reload.
  const other = await openTab();
  await other.go("/examples/chat");
  await other.clickLink("Join the room");
  await other.evaluate(`document.querySelector("input[type=text]").value = "pusher"`);
  await other.evaluate(`document.querySelector("button[type=submit]").click()`); await other.waitLoad();
  await sleep(500);                                  // let the first tab's stream settle
  await other.evaluate(`(() => { const d = document.getElementById("draft"); d.value = "pushed across sessions";
                                 d.form.requestSubmit(); })()`);
  await sleep(1000);
  check("push reaches another session",
        (await evaluate(`document.querySelector(".chat-messages").innerText`)).includes("pushed across sessions"));
  check("push did not reload", await evaluate("window.__chat") === 1);
  await other.close();

  // A background job reports progress through notify.
  await go("/examples/progress");
  await evaluate(`document.querySelector("button").click()`);
  await sleep(4500);
  check("background job progress pushed", (await evaluate("document.body.innerText")).includes("Done."));

  // Widgets: typing into the autocomplete, then choosing a suggestion.
  await go("/examples/widgets");
  await clickLink("Autocomplete");
  await evaluate(`document.getElementById("symbol").focus()`);
  await send("Input.insertText", { text: "mapca" });
  await sleep(700);
  const suggestions = await evaluate(`[...document.querySelectorAll(".lt-suggestion")].map(b => b.textContent)`);
  check("autocomplete suggests", suggestions.includes("mapcar") && suggestions.includes("mapcan"), JSON.stringify(suggestions));
  await evaluate(`[...document.querySelectorAll(".lt-suggestion")].find(b => b.textContent === "mapcar").click()`);
  await sleep(600);
  check("choosing a suggestion fills the field", await evaluate(`document.getElementById("symbol").value`) === "mapcar");

  // Dragging an item in the sortable list.
  await clickLink("Sortable");
  await evaluate(`(() => {
    const items = () => [...document.querySelectorAll("[data-lt-sortable] > li")];
    const first = items()[0], last = items()[3];
    const data = new DataTransfer();
    const box = last.getBoundingClientRect();
    first.dispatchEvent(new DragEvent("dragstart", { bubbles: true, dataTransfer: data }));
    last.dispatchEvent(new DragEvent("dragover", { bubbles: true, cancelable: true, dataTransfer: data,
                                                   clientY: box.bottom - 1 }));
    last.dispatchEvent(new DragEvent("drop", { bubbles: true, cancelable: true, dataTransfer: data }));
    first.dispatchEvent(new DragEvent("dragend", { bubbles: true, dataTransfer: data }));
  })()`);
  await sleep(700);
  await send("Page.reload"); await waitLoad();
  check("drag reorders on the server",
        (await evaluate("document.body.innerText")).includes("Order: Make them pass, Refactor, Ship it, Write the tests"));

  // Tracker: two people; the second's list updates live when the first files an issue.
  const press = async (t, label) => {
    await t.evaluate(`[...document.querySelectorAll("button")].find(b => b.textContent.includes(${JSON.stringify(label)})).click()`);
    await t.waitLoad();
  };
  const fill = (t, id, value) =>
    t.evaluate(`document.getElementById(${JSON.stringify(id)}).value = ${JSON.stringify(value)}`);
  const signUp = async (t, name) => {
    await t.go("/tracker");
    await t.clickLink("create an account");
    await fill(t, "name", name); await fill(t, "email", name + "@example.org");
    await fill(t, "password", "correct horse"); await fill(t, "confirm", "correct horse");
    await press(t, "Create account");
  };
  const stamp = Date.now().toString(36);
  const me = { evaluate, waitLoad, go, clickLink };
  await signUp(me, "ada" + stamp);
  const watcher = await openTab();
  await signUp(watcher, "bob" + stamp);
  await watcher.evaluate("window.__tracker = 1");
  await sleep(500);
  await clickLink("New issue");
  await fill(me, "title", "Live issue " + stamp);
  await press(me, "File issue");
  check("issue filed", (await evaluate("document.body.innerText")).includes("Live issue " + stamp));
  await sleep(1200);
  check("other user's list updates live",
        (await watcher.evaluate("document.body.innerText")).includes("Live issue " + stamp));
  check("without a reload", await watcher.evaluate("window.__tracker") === 1);
  await watcher.close();

  // A dialog over the page: focus moves in, Esc closes it; toasts appear.
  await go("/examples/dialogs");
  await clickLink("Open a dialog");
  check("dialog opens over the page",
        await evaluate(`!!document.querySelector("dialog.lt-modal") && !!document.querySelector(".lt-behind-modal[inert]")`));
  check("focus moves into the dialog", await evaluate(`document.querySelector("dialog.lt-modal").contains(document.activeElement)`));
  await send("Input.dispatchKeyEvent", { type: "keyDown", key: "Escape", code: "Escape", windowsVirtualKeyCode: 27 });
  await send("Input.dispatchKeyEvent", { type: "keyUp", key: "Escape", code: "Escape", windowsVirtualKeyCode: 27 });
  await waitLoad(); await sleep(300);
  check("Esc closes the dialog", await evaluate(`!document.querySelector("dialog.lt-modal")`));
  await evaluate(`document.getElementById("toast-button").click()`); await sleep(600);
  check("a toast appears", (await evaluate(`document.querySelector(".lt-toasts")?.innerText || ""`)).includes("Hello from the server."));

  // Parenscript: a browser-only handler, and a call to a Lisp function.
  await go("/examples/parenscript");
  await evaluate("window.__ps = 1");
  await evaluate(`document.getElementById("toggle").click()`);
  check("browser-only handler ran", await evaluate(`document.getElementById("toggle").textContent`) === "On");
  await evaluate(`document.getElementById("shout").click()`); await sleep(700);
  check("littoral.call returns the Lisp answer",
        await evaluate(`document.getElementById("answer").textContent`) === "HELLO FROM THE BROWSER");
  check("and updates the component", (await evaluate("document.body.innerText")).includes("Asked 1 time."));
  check("without a reload", await evaluate("window.__ps") === 1);

  // The generated admin: list, open a task, follow its project.
  await go("/examples/admin");
  check("admin lists projects", (await evaluate("document.body.innerText")).includes("Littoral"));
  await clickLink("Tasks");
  // Search updates as you type; the caret stays put while results swap in.
  await evaluate(`document.getElementById("search").focus()`);
  for (const ch of "admin") { await send("Input.insertText", { text: ch }); await sleep(60); }
  await sleep(900);
  check("typing while results swap keeps order", await evaluate(`document.getElementById("search").value`) === "admin",
        await evaluate(`document.getElementById("search").value`));
  check("search filters", (await evaluate("document.body.innerText")).includes("Admin interface"));
  await go("/examples/admin");
  await clickLink("Tasks");
  await evaluate(`document.querySelector(".lt-report tbody a").click()`); await waitLoad();
  check("admin opens a task", /Task #\d+/.test(await evaluate("document.body.innerText")));

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
