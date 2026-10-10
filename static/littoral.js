// littoral.js — AJAX updates for Littoral pages.
//
// Elements carry data-lt-on-click / data-lt-on-change / data-lt-on-input
// = "CALLBACK;ID ID…", or data-lt-periodical = "MS;CALLBACK;ID ID…".
// The callback (if any) is posted to the page's action URL with the
// element's field (or whole form, for a submit button), and the
// components named are replaced with their freshly rendered HTML.
(function () {
  "use strict";

  function actionUrl() {
    return document.body.getAttribute("data-lt-action");
  }

  function fieldParams(el, params) {
    if (!el.name) return;
    if (el.type === "checkbox") {
      params.append(el.name, el.checked ? "on" : "off");
    } else {
      params.append(el.name, el.value);
    }
  }

  // Browser code.  The page defines its code in its own script, under ids
  // (window.__ltCode); attributes name it as "@id" and never hold code, so
  // markup injected into the page can't bring code past the content
  // security policy.  Code arriving later (AJAX, push) is defined through
  // script elements carrying the page's nonce, never eval.
  var NONCE = (document.currentScript && document.currentScript.nonce) || null;
  window.__ltCode = window.__ltCode || {};
  function makeFunction(params, body) {
    if (!NONCE) return Function.apply(null, params.concat([body]));
    var key = "__lt" + Math.random().toString(36).slice(2);
    var s = document.createElement("script");
    s.nonce = NONCE;
    s.textContent = "window." + key + "=function(" + params.join(",") + "){" + body + "\n};";
    document.head.appendChild(s); s.remove();
    var f = window[key]; delete window[key];
    return f || function () {};
  }
  function code(ref) {
    return ref && ref.charAt(0) === "@" ? window.__ltCode[ref.slice(1)] || null : null;
  }

  // The page's WebSocket, when it has one open (littoral/websocket).
  var socket = null, nextId = 1, waiting = {};

  // Send an AJAX request over the socket if it is open, else by fetch.
  function send(params) {
    if (socket && socket.readyState === 1) {
      return new Promise(function (resolve) {
        var id = nextId++, object = {};
        params.forEach(function (v, k) { object[k] = v; });
        waiting[id] = resolve;
        socket.send(JSON.stringify({ id: id, params: object }));
      });
    }
    return fetch(actionUrl(), {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: params.toString(),
      credentials: "same-origin"
    }).then(function (r) {
      // In development, a failed request answers with the debugger page.
      if (!r.ok && r.headers.get("X-Littoral-Debugger"))
        return r.text().then(function (html) { showDebugger(html); throw debuggerShown; });
      if (!r.ok) throw new Error("HTTP " + r.status);
      return r.json();
    });
  }

  var debuggerShown = new Error("debugger shown");
  function showDebugger(html) {
    document.open(); document.write(html); document.close();
  }

  // The focused field and its value, as a request leaves.
  function fieldState() {
    var active = document.activeElement;
    return active && active.id && typeof active.value === "string" ? { id: active.id, value: active.value } : null;
  }

  function post(callback, targets, params, el, attr) {
    params.append("_lt_ajax", "1");
    params.append("_lt_update", targets);
    if (callback) params.append(callback, "1");
    var sent = fieldState();
    return send(params)
      .then(function (data) {
        apply(data, sent);
        var complete = el && attr && el.getAttribute(attr + "-complete");
        var done = code(complete);
        if (done) done.call(el, data.value);
      })
      .catch(function (e) { if (e !== debuggerShown) window.location.reload(); });
  }

  // Swap in the components a response or a pushed event carries.
  // Toasts: brief messages at the corner of the page.
  function toastContainer() {
    var box = document.querySelector(".lt-toasts");
    if (!box) {
      box = document.createElement("div");
      box.className = "lt-toasts"; box.setAttribute("aria-live", "polite"); box.setAttribute("role", "status");
      document.body.appendChild(box);
    }
    return box;
  }
  function dismissLater(toast) {
    setTimeout(function () { toast.classList.add("lt-toast-leaving"); }, 5000);
    setTimeout(function () { if (toast.parentNode) toast.parentNode.removeChild(toast); }, 5600);
  }
  function showToasts(toasts) {
    var box = toastContainer();
    (toasts || []).forEach(function (t) {
      var el = document.createElement("div");
      el.className = "lt-toast lt-toast-" + t.kind;
      el.textContent = t.text;
      box.appendChild(el);
      dismissLater(el);
    });
  }

  // Modal dialogs: focus goes in, Tab stays in, Esc closes a closable one.
  function focusables(dialog) {
    return Array.prototype.filter.call(
      dialog.querySelectorAll("a[href], button, input, select, textarea, [tabindex]:not([tabindex='-1'])"),
      function (el) { return !el.disabled && el.type !== "hidden"; });
  }
  function setupModal() {
    var dialog = document.querySelector("dialog.lt-modal");
    if (!dialog) return;
    var items = focusables(dialog);
    var first = items.filter(function (el) { return !el.classList.contains("lt-modal-close"); })[0] || items[0];
    if (first && !dialog.contains(document.activeElement)) first.focus();
  }
  document.addEventListener("keydown", function (event) {
    var dialog = document.querySelector("dialog.lt-modal");
    if (!dialog) return;
    if (event.key === "Escape" && dialog.getAttribute("data-lt-modal") === "closable") {
      var close = dialog.querySelector(".lt-modal-close");
      if (close) { event.preventDefault(); close.click(); }
    } else if (event.key === "Tab") {
      var items = focusables(dialog);
      if (!items.length) return;
      var first = items[0], last = items[items.length - 1];
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
      else if (!dialog.contains(document.activeElement)) { event.preventDefault(); first.focus(); }
    }
  });

  // SENT: the focused field as the request left (NIL for pushes).
  function apply(data, sent) {
    if (data.redirect) { window.location.href = data.redirect; return; }
    // Code the new fragments use, defined before they arrive.
    (data.code || []).forEach(function (c) { window.__ltCode[c[0]] = makeFunction(c[1], c[2]); });
    showToasts(data.toasts);
    var active = document.activeElement;
    var focused = active && active.id;
    var live = active && typeof active.value === "string" && /^(INPUT|TEXTAREA)$/.test(active.tagName) &&
               !/^(checkbox|radio|file|submit|button)$/.test(active.type)
      ? { value: active.value, start: active.selectionStart, end: active.selectionEnd } : null;
    Object.keys(data.fragments).forEach(function (id) {
      var old = document.getElementById(id);
      if (!old) return;
      if (old.hasAttribute("aria-live")) {
        // Keep a live region's element, so screen readers announce the
        // change instead of losing the region.
        var holder = document.createElement("div");
        holder.innerHTML = data.fragments[id];
        var replacement = holder.firstElementChild;
        if (replacement) {
          old.innerHTML = replacement.innerHTML;
          old.className = replacement.className;
        }
      } else {
        old.outerHTML = data.fragments[id];
      }
      // outerHTML drops focus; give it back, or honour autofocus.
      var fresh = document.getElementById(id);
      var target = (focused && fresh.querySelector("#" + CSS.escape(focused))) ||
                   fresh.querySelector("[autofocus]");
      if (target && target.focus) target.focus();
      // Typing goes on while a request is out: when the server sent back the
      // value it was given, keep what has been typed since, and the caret.
      // A value the server changed (a cleared message box) stands.
      if (live && target && target.id === focused && typeof target.value === "string" &&
          (!sent || (sent.id === focused && target.value === sent.value))) {
        target.value = live.value;
        try { target.setSelectionRange(live.start, live.end); } catch (e) {}
      }
    });
    if (data.missing.length) window.location.reload();
    (data.scripts || []).forEach(function (script) { makeFunction([], script)(); });
    scanPeriodicals();
    document.dispatchEvent(new CustomEvent("littoral:updated",
      { detail: { ids: Object.keys(data.fragments) } }));
  }

  // Server push: pages showing subscribed components listen for updates.
  function listenOnSocket(url, fallback) {
    var opened = false;
    var ws = new WebSocket((location.protocol === "https:" ? "wss://" : "ws://") + location.host + url);
    ws.onopen = function () { opened = true; socket = ws; };
    ws.onmessage = function (event) {
      var message = JSON.parse(event.data);
      if (message.type === "reply") {
        if (message.data && message.data.debugger) { showDebugger(message.data.debugger); return; }
        var resolve = waiting[message.id]; delete waiting[message.id];
        if (resolve) resolve(message.data);
      } else if (message.type === "update") {
        apply(message.data);
      } else if (message.type === "toast") {
        showToasts(message.data);
      } else if (message.type === "reload") {
        ws.close(); window.location.reload();
      }
    };
    ws.onclose = function () {
      socket = null;
      if (!opened) fallback();          // never connected: use server-sent events
    };
    window.addEventListener("pagehide", function () { ws.close(); });
  }

  function listen() {
    var wsUrl = document.body.getAttribute("data-lt-ws");
    if (wsUrl && window.WebSocket) {
      listenOnSocket(wsUrl, listenForEvents);
      return;
    }
    listenForEvents();
  }

  function listenForEvents() {
    var url = document.body.getAttribute("data-lt-events");
    if (!url || !window.EventSource) return;
    var source = new EventSource(url);
    source.addEventListener("update", function (event) {
      apply(JSON.parse(event.data));
    });
    source.addEventListener("toast", function (event) {
      showToasts(JSON.parse(event.data));
    });
    // Live redefinition: the server's code changed; draw this page again.
    source.addEventListener("reload", function () {
      source.close();
      window.location.reload();
    });
    window.addEventListener("pagehide", function () { source.close(); });
  }

  function split(spec) {
    var i = spec.indexOf(";");
    return { callback: spec.slice(0, i), targets: spec.slice(i + 1) };
  }

  function trigger(el, attr, event) {
    var spec = split(el.getAttribute(attr));
    var question = el.getAttribute(attr + "-confirm");
    if (question && !window.confirm(question)) {
      if (event) event.preventDefault();
      return;
    }
    var params = new URLSearchParams();
    var valueExpression = el.getAttribute(attr + "-value");
    if (valueExpression) {
      var compute = code(valueExpression);
      var value = compute ? compute.call(el) : null;
      params.append("_lt_value", value == null ? "" : String(value));
    }
    if (el.form && (el.type === "submit" || attr === "data-lt-on-submit")) {
      new FormData(el.form).forEach(function (v, k) {
        if (typeof v === "string") params.append(k, v);
      });
    } else if (el.tagName === "FORM") {
      new FormData(el).forEach(function (v, k) {
        if (typeof v === "string") params.append(k, v);
      });
    } else {
      fieldParams(el, params);
    }
    if (event) event.preventDefault();
    post(spec.callback, spec.targets, params, el, attr);
  }

  function delegate(type, attr) {
    document.addEventListener(type, function (event) {
      var el = event.target.closest ? event.target.closest("[" + attr + "]") : null;
      if (el) trigger(el, attr, type === "click" || type === "submit" ? event : null);
    });
  }

  delegate("click", "data-lt-on-click");
  delegate("change", "data-lt-on-change");
  delegate("input", "data-lt-on-input");
  delegate("submit", "data-lt-on-submit");

  // Browser-only handlers, written in Parenscript (littoral/parenscript).
  function clientDelegate(type, attr) {
    document.addEventListener(type, function (event) {
      var el = event.target.closest ? event.target.closest("[" + attr + "]") : null;
      var handler = el && code(el.getAttribute(attr));
      if (handler) handler.call(el, event);
    });
  }
  clientDelegate("click", "data-lt-on-click-js");
  clientDelegate("change", "data-lt-on-change-js");
  clientDelegate("input", "data-lt-on-input-js");
  clientDelegate("submit", "data-lt-on-submit-js");

  // Call a Lisp function registered with client-callback; a promise of its answer.
  window.littoral = {
    call: function (spec, value) {
      var parts = split(spec), params = new URLSearchParams();
      if (value !== undefined) params.append("_lt_value", value == null ? "" : String(value));
      params.append("_lt_ajax", "1");
      params.append("_lt_update", parts.targets);
      params.append(parts.callback, "1");
      return send(params).then(function (data) { apply(data); return data.value; });
    },
    // How AJAX requests travel just now: "websocket" or "fetch".
    transport: function () { return socket && socket.readyState === 1 ? "websocket" : "fetch"; }
  };

  // Sortable lists: drag an item over its siblings; on release, post the
  // new order (old positions, comma-separated) through the list's callback.
  var dragged = null;
  function sortableItem(target) {
    return target.closest ? target.closest("[data-lt-sortable] > li") : null;
  }
  document.addEventListener("dragstart", function (event) {
    var item = sortableItem(event.target);
    if (!item) return;
    dragged = item;
    event.dataTransfer.effectAllowed = "move";
    event.dataTransfer.setData("text/plain", "");
    item.classList.add("lt-dragging");
  });
  document.addEventListener("dragover", function (event) {
    if (!dragged) return;
    var item = sortableItem(event.target);
    if (!item || item.parentNode !== dragged.parentNode) return;
    event.preventDefault();
    if (item === dragged) return;
    var box = item.getBoundingClientRect();
    var after = event.clientY > box.top + box.height / 2;
    item.parentNode.insertBefore(dragged, after ? item.nextSibling : item);
  });
  document.addEventListener("drop", function (event) {
    if (dragged) event.preventDefault();
  });
  document.addEventListener("dragend", function () {
    if (!dragged) return;
    var list = dragged.parentNode;
    dragged.classList.remove("lt-dragging");
    dragged = null;
    var order = Array.prototype.map.call(list.children, function (li) {
      return li.getAttribute("data-lt-index");
    });
    var moved = order.some(function (index, position) { return Number(index) !== position; });
    if (!moved) return;
    list.dataset.order = order.join(",");
    trigger(list, "data-lt-sortable", null);
  });

  // Kanban boards: drag a card within its column or to another; on release,
  // post "from-column,from-index,to-column,to-index" through the board's callback.
  var card = null, cardFrom = null;
  function kanbanCard(target) {
    return target.closest ? target.closest("[data-lt-kanban] ol > li") : null;
  }
  document.addEventListener("dragstart", function (event) {
    var item = kanbanCard(event.target);
    if (!item) return;
    card = item;
    cardFrom = [item.parentNode.getAttribute("data-lt-column"), item.getAttribute("data-lt-index")];
    event.dataTransfer.effectAllowed = "move";
    event.dataTransfer.setData("text/plain", "");
    item.classList.add("lt-dragging");
  });
  document.addEventListener("dragover", function (event) {
    if (!card) return;
    var board = card.closest("[data-lt-kanban]");
    var list = event.target.closest ? event.target.closest("[data-lt-kanban] ol") : null;
    if (!list || list.closest("[data-lt-kanban]") !== board) return;
    event.preventDefault();
    var over = kanbanCard(event.target);
    if (over === card) return;
    if (over && over.parentNode === list) {
      var box = over.getBoundingClientRect();
      list.insertBefore(card, event.clientY > box.top + box.height / 2 ? over.nextSibling : over);
    } else if (!over) {
      list.appendChild(card);
    }
  });
  document.addEventListener("dragend", function () {
    if (!card) return;
    var board = card.closest("[data-lt-kanban]");
    var to = [card.parentNode.getAttribute("data-lt-column"),
              String(Array.prototype.indexOf.call(card.parentNode.children, card))];
    card.classList.remove("lt-dragging");
    card = null;
    if (to[0] === cardFrom[0] && to[1] === cardFrom[1]) return;
    board.dataset.move = cardFrom.concat(to).join(",");
    trigger(board, "data-lt-kanban", null);
  });

  var timers = [];
  function scanPeriodicals() {
    timers.forEach(clearInterval);
    timers = [];
    document.querySelectorAll("[data-lt-periodical]").forEach(function (el) {
      var spec = el.getAttribute("data-lt-periodical");
      var i = spec.indexOf(";");
      var ms = parseInt(spec.slice(0, i), 10);
      var rest = split(spec.slice(i + 1));
      timers.push(setInterval(function () {
        post(rest.callback, rest.targets, new URLSearchParams());
      }, ms));
    });
  }

  // Live redefinition on pages without an event stream: ask now and then
  // whether code this page shows has changed.
  function pollForReload() {
    var url = document.body.getAttribute("data-lt-live");
    if (!url) return;
    var timer = setInterval(function () {
      fetch(url, { credentials: "same-origin" })
        .then(function (r) { return r.ok ? r.json() : { reload: false }; })
        .then(function (answer) {
          if (answer.reload) { clearInterval(timer); window.location.reload(); }
        })
        .catch(function () {});
    }, 1500);
    window.addEventListener("pagehide", function () { clearInterval(timer); });
  }

  document.addEventListener("DOMContentLoaded", function () {
    scanPeriodicals();
    listen();
    pollForReload();
    setupModal();
    Array.prototype.forEach.call(document.querySelectorAll(".lt-toast"), dismissLater);
  });

  // A page restored from the back/forward cache shows state the server may
  // have moved past (an isolated checkout, say), and Chrome restores even
  // no-store pages.  Ask the server again.
  window.addEventListener("pageshow", function (event) {
    if (event.persisted) window.location.reload();
  });
})();
