// Accessibility audit: axe-core (WCAG 2 A and AA rules) over every example
// page and the states reached by acting on them, in headless Chrome.
//   make a11y
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
await send("Page.enable"); await send("Runtime.enable"); await send("Log.enable");
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


const AXE = "https://unpkg.com/axe-core@4.10.2/axe.min.js";
const axeSource = await (await fetch(AXE)).text();
let failures = 0;
const results = [];

// Content security policy: no page may break its own policy, except the
// demonstration page that breaks it on purpose.
let seenEvents = 0;
function checkPolicy(label) {
  const fresh = events.slice(seenEvents); seenEvents = events.length;
  const violations = fresh.filter((e) => e.method === "Log.entryAdded" &&
                                         /Content Security Policy/.test(e.params.entry.text));
  if (violations.length && !label.includes("/examples/csp")) {
    failures++;
    console.log(`FAIL ${label}: content security policy violation: ${violations[0].params.entry.text.slice(0, 200)}`);
  }
}

async function auditAs(label) {
  checkPolicy(label);
  await evaluate(axeSource);
  const found = await evaluate(`axe.run(document, { runOnly: ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"] })
    .then(r => r.violations.map(v => ({ id: v.id, impact: v.impact, help: v.help,
                                        nodes: v.nodes.slice(0, 3).map(n => n.target.join(" ")) })))`);
  results.push({ label, found });
  for (const v of found) {
    console.log(`${v.impact.padEnd(8)} ${label}: ${v.id} — ${v.help} [${v.nodes.join(" | ")}]`);
    if (v.impact === "serious" || v.impact === "critical") failures++;
  }
}

const pages = ["/examples", "/examples/counter", "/examples/multi-counter", "/examples/guess",
  "/examples/login", "/examples/ajax", "/examples/todo", "/examples/upload", "/examples/topics",
  "/examples/report", "/examples/store", "/examples/wiki", "/examples/chat", "/examples/progress",
  "/examples/contacts", "/examples/widgets", "/tracker", "/config", "/tutorial/reading-list",
  "/examples/admin", "/examples/dialogs", "/examples/parenscript", "/examples/members", "/examples/demo-idp", "/examples/accounts", "/examples/gallery", "/examples/csp", "/examples/api", "/examples/devtools", "/examples/monitoring", "/examples/wizard", "/examples/search", "/examples/mail"];

try {
 // Both colour schemes: contrast differs between them.
 for (const scheme of ["light", "dark"]) {
  await send("Emulation.setEmulatedMedia", { features: [{ name: "prefers-color-scheme", value: scheme }] });
  const audit = (label) => auditAs(`${label} (${scheme})`);
  for (const page of pages) { await go(page); await audit(page); }
  // States reached by acting.
  await go("/examples/contacts"); await clickLink("Add a contact");
  await evaluate(`[...document.querySelectorAll("button")].find(b => b.textContent === "Add").click()`); await waitLoad();
  await audit("contacts editor with errors");
  await go("/examples/login"); await clickLink("Log in"); await audit("login dialog");
  await go("/examples/widgets");
  for (const tab of ["Tree", "Autocomplete", "Sortable", "Data grid", "Charts", "Calendar", "Kanban", "Markdown"]) {
    await clickLink(tab); await audit("widgets: " + tab);
  }
  await go("/examples/store");
  await evaluate(`document.querySelector("a.add").click()`); await waitLoad();
  await clickLink("Checkout"); await audit("store: cart review");
  await go("/tracker"); await clickLink("create an account"); await audit("tracker: registration");
  await go("/examples/dialogs"); await clickLink("Open a dialog"); await audit("dialog open");
  await go("/examples/wizard"); await clickLink("Sign up"); await audit("wizard step");
  await go("/examples/counter"); await clickLink("Halos"); await audit("halos");
  await clickLink("Halos off");
 }

 // Phone width: nothing may stick out past the screen's right edge, except
 // inside something that scrolls sideways (a wide table, code).
 await send("Emulation.setDeviceMetricsOverride", { width: 360, height: 740, deviceScaleFactor: 2, mobile: true });
 const overflow = () => evaluate(`(() => {
   const w = document.documentElement.clientWidth, out = [];
   const scrolls = (el) => { for (let p = el.parentElement; p; p = p.parentElement) {
     const o = getComputedStyle(p).overflowX; if (o === "auto" || o === "scroll" || o === "hidden") return true; } return false; };
   for (const el of document.body.querySelectorAll("*")) {
     const r = el.getBoundingClientRect();
     if (r.width && r.right > w + 1 && !scrolls(el))
       out.push(el.tagName.toLowerCase() + (el.id ? "#" + el.id : "") + (el.className && typeof el.className === "string" ? "." + el.className.trim().split(/\s+/).join(".") : "") + " to " + Math.round(r.right) + "px");
   }
   if (document.documentElement.scrollWidth > w + 1) out.unshift("page " + document.documentElement.scrollWidth + "px wide");
   return out.slice(0, 4);
 })()`);
 const phoneCheck = async (label) => {
   const found = await overflow();
   if (found.length) { failures++; console.log(`FAIL ${label} at 360px: ${found.join(", ")}`); }
   else console.log(`PASS ${label} at 360px`);
 };
 for (const page of pages) { await go(page); await phoneCheck(page); }
 await go("/examples/contacts"); await clickLink("Add a contact"); await phoneCheck("contacts editor");
 await go("/examples/widgets");
 for (const tab of ["Tree", "Autocomplete", "Sortable"]) { await clickLink(tab); await phoneCheck("widgets: " + tab); }
 await go("/examples/counter"); await clickLink("Halos"); await phoneCheck("halos");
 await clickLink("Halos off");
} catch (e) { console.log("ERROR " + e.message); failures++; }
finally {
  ws.close(); chrome.kill();
  await sleep(300);
  (await import("node:fs")).rmSync(PROFILE, { recursive: true, force: true });
}
const total = results.reduce((n, r) => n + r.found.length, 0);
console.log(`\n${results.length} pages, ${total} violations, ${failures} serious or critical`);
process.exit(failures ? 1 : 0);
