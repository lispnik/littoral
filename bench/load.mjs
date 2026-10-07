// load.mjs — measure littoral over real HTTP.  Start bench/load-server.lisp
// first (make load does both).  Node 22+, no packages.
const BASE = process.env.BASE || "http://127.0.0.1:8095";
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// A virtual user: keeps cookies, follows redirects, remembers the page.
class User {
  constructor() { this.cookies = new Map(); this.url = null; this.html = ""; }
  cookieHeader() { return [...this.cookies].map(([k, v]) => `${k}=${v}`).join("; "); }
  async get(path) {
    let url = path;
    for (let i = 0; i < 5; i++) {
      const r = await fetch(BASE + url, { redirect: "manual", headers: { cookie: this.cookieHeader() } });
      for (const c of r.headers.getSetCookie()) {
        const [pair] = c.split(";"); const eq = pair.indexOf("=");
        this.cookies.set(pair.slice(0, eq), pair.slice(eq + 1));
      }
      if (r.status === 302) { await r.arrayBuffer(); url = r.headers.get("location"); continue; }
      this.status = r.status; this.url = url; this.html = await r.text();
      return this;
    }
    throw new Error("too many redirects");
  }
  link(text) {
    const m = this.html.match(new RegExp(`<a href="([^"]*)"[^>]*>${text}</a>`));
    if (!m) throw new Error(`no link ${text} on ${this.url} (${this.status})`);
    return m[1].replaceAll("&amp;", "&");
  }
}

const stats = async () => (await fetch(BASE + "/_stats")).json();
const percentile = (sorted, p) => sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * p))];
const mb = (bytes) => (bytes / 1048576).toFixed(1) + " MB";

async function clicks(path, link, users, seconds) {
  const people = await Promise.all(Array.from({ length: users }, () => new User().get(path)));
  const latencies = []; let errors = 0; let firstError = null;
  const end = Date.now() + seconds * 1000;
  await Promise.all(people.map(async (u) => {
    while (Date.now() < end) {
      const t = performance.now();
      try { await u.get(u.link(link)); latencies.push(performance.now() - t); }
      catch (e) { if (!errors++) firstError = e.message; await u.get(path); }
    }
  }));
  latencies.sort((a, b) => a - b);
  return { clicks: latencies.length, perSecond: Math.round(latencies.length / seconds), errors, firstError,
           p50: percentile(latencies, 0.5).toFixed(1), p95: percentile(latencies, 0.95).toFixed(1),
           p99: percentile(latencies, 0.99).toFixed(1) };
}

async function sessionMemory(path, link, count, clicksEach) {
  const before = await stats();
  for (let i = 0; i < count; i += 50) {
    await Promise.all(Array.from({ length: Math.min(50, count - i) }, async () => {
      const u = await new User().get(path);
      for (let k = 0; k < clicksEach; k++) await u.get(u.link(link));
    }));
  }
  const after = await stats();
  return { sessions: after.sessions - before.sessions,
           perSession: Math.round((after.heap - before.heap) / (after.sessions - before.sessions)),
           heap: after.heap };
}

// Open N event streams from separate users, in batches; then time an
// ordinary request while they are open.
async function retrying(f, attempts = 5) {
  for (let i = 1; ; i++) {
    try { return await f(); } catch (e) { if (i >= attempts) throw e; await sleep(100 * i); }
  }
}

async function streams(n, pid) {
  const controllers = []; let opened = 0, refused = 0;
  const received = new Set();
  for (let i = 0; i < n; i += 25) {
    await Promise.all(Array.from({ length: Math.min(25, n - i) }, async () => {
      try {
        const u = await retrying(() => new User().get("/progress"));
        const m = u.html.match(/data-lt-events="([^"]*)"/);
        const controller = new AbortController(); controllers.push(controller);
        const r = await retrying(() => fetch(BASE + m[1].replaceAll("&amp;", "&"),
                                            { headers: { cookie: u.cookieHeader() }, signal: controller.signal }));
        if (r.status === 200) {
          opened++;
          const id = opened;
          (async () => {
            const reader = r.body.getReader(); const decoder = new TextDecoder();
            try {
              for (;;) {
                const { value, done } = await reader.read();
                if (done) break;
                if (decoder.decode(value).includes("event: update")) received.add(id);
              }
            } catch {}
          })();
        } else refused++;
      } catch { refused++; }
    }));
  }
  await sleep(500);
  // Push to every open page and count how many hear it.
  const publishedTo = Number(await (await fetch(BASE + "/_publish")).text());
  await sleep(Math.max(1000, n * 2));
  const delivered = received.size;
  const s = await stats();
  const t = performance.now(); let ok = true;
  try {
    const r = await fetch(BASE + "/counter", { redirect: "manual", signal: AbortSignal.timeout(5000) });
    ok = r.status === 302;
  } catch { ok = false; }
  const probeMs = performance.now() - t;
  let rss = null;
  if (pid) {
    const { execSync } = await import("node:child_process");
    rss = Math.round(Number(execSync(`ps -o rss= -p ${pid}`).toString().trim()) / 1024) + " MB";
  }
  controllers.forEach((c) => c.abort());
  await sleep(Number(process.env.SETTLE_MS || 8000));
  return { requested: n, opened, refused, publishedTo, delivered, serverStreams: s.streams, threads: s.threads,
           heap: mb(s.heap), rss, otherRequest: ok ? `${probeMs.toFixed(0)} ms` : "timed out" };
}

const mode = process.argv[2] || "all";
const out = {};
// One click run, for several clients at once: CLICK_PATH, CLICK_LINK, USERS, SECONDS.
if (mode === "click") {
  out.click = await clicks(process.env.CLICK_PATH || "/counter", process.env.CLICK_LINK || "\\+\\+",
                           Number(process.env.USERS || 16), Number(process.env.SECONDS || 10));
}
if (mode === "all" || mode === "clicks") {
  out.counter_8 = await clicks("/counter", "\\+\\+", 8, 10);
  out.counter_32 = await clicks("/counter", "\\+\\+", 32, 10);
  out.store_32 = await clicks("/store", "Add", 32, 10);
}
if (mode === "all" || mode === "memory") {
  out.memory_counter = await sessionMemory("/counter", "\\+\\+", 1000, 5);
  out.memory_store = await sessionMemory("/store", "Add", 500, 5);
}
if (mode === "all" || mode === "streams") {
  const levels = (process.env.STREAMS || "50,95,150").split(",").map(Number);
  for (const n of levels) out[`streams_${n}`] = await streams(n, process.env.SERVER_PID);
}
console.log(JSON.stringify(out, null, 2));
