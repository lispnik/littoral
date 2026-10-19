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
    // The session is gone (a restart): load the page afresh.
    if (data.reload) { window.location.reload(); return; }
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

  // Passkeys (littoral/auth): a button carries navigator.credentials options
  // (binary fields in base 64 URL) and the callback that receives the answer.
  function fromB64url(s) {
    s = s.replace(/-/g, "+").replace(/_/g, "/"); while (s.length % 4) s += "=";
    var b = atob(s), a = new Uint8Array(b.length);
    for (var i = 0; i < b.length; i++) a[i] = b.charCodeAt(i);
    return a.buffer;
  }
  function toB64url(buffer) {
    var b = "", a = new Uint8Array(buffer);
    for (var i = 0; i < a.length; i++) b += String.fromCharCode(a[i]);
    return btoa(b).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  }
  document.addEventListener("click", function (event) {
    var button = event.target.closest ? event.target.closest("[data-lt-passkey]") : null;
    if (!button) return;
    event.preventDefault();
    var status = document.getElementById(button.getAttribute("data-lt-passkey-status") || "");
    var say = function (text) { if (status) status.textContent = text; };
    if (!window.PublicKeyCredential) { say("This browser doesn't support passkeys."); return; }
    var options = JSON.parse(button.getAttribute("data-lt-passkey-options"));
    options.challenge = fromB64url(options.challenge);
    var create = button.getAttribute("data-lt-passkey") === "create";
    if (create) options.user.id = fromB64url(options.user.id);
    (options.allowCredentials || options.excludeCredentials || []).forEach(function (c) { c.id = fromB64url(c.id); });
    var request = create ? navigator.credentials.create({ publicKey: options })
                         : navigator.credentials.get({ publicKey: options });
    request.then(function (credential) {
      var r = credential.response, response = { clientDataJSON: toB64url(r.clientDataJSON) };
      if (create) response.attestationObject = toB64url(r.attestationObject);
      else {
        response.authenticatorData = toB64url(r.authenticatorData);
        response.signature = toB64url(r.signature);
        if (r.userHandle) response.userHandle = toB64url(r.userHandle);
      }
      return window.littoral.call(button.getAttribute("data-lt-passkey-callback"),
                                  JSON.stringify({ id: credential.id, type: credential.type, response: response }));
    }).catch(function (e) { say(e && e.name === "NotAllowedError" ? "Cancelled." : "That didn't work."); });
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

  // Tags fields: the comma-separated input hides, and chips with remove
  // buttons and a box to type the next tag in take its place.  The hidden
  // input keeps the text the form sends, so the server sees what it would
  // without JavaScript.
  function setupTags(root) {
    (root || document).querySelectorAll("input[data-lt-tags]:not([data-lt-tags-ready])").forEach(function (input) {
      input.setAttribute("data-lt-tags-ready", "");
      var removeLabel = input.getAttribute("data-lt-tags");
      var box = document.createElement("div");
      box.className = "lt-tags-input";
      var chips = document.createElement("ul");
      chips.className = "lt-tags";
      var entry = document.createElement("input");
      entry.type = "text";
      entry.className = "lt-tags-entry";
      entry.autocomplete = "off";
      // Labels and descriptions point at what is typed into.
      ["list", "aria-label", "aria-invalid", "aria-describedby", "aria-description", "autofocus"].forEach(function (a) {
        if (input.hasAttribute(a)) entry.setAttribute(a, input.getAttribute(a));
      });
      if (input.id) { entry.id = input.id; input.id = input.id + "-value"; }
      input.type = "hidden";
      input.removeAttribute("required");
      function tags() {
        return input.value.split(",").map(function (t) { return t.trim(); }).filter(Boolean);
      }
      function write(list) {
        input.value = list.join(", ");
        input.dispatchEvent(new Event("input", { bubbles: true }));
        input.dispatchEvent(new Event("change", { bubbles: true }));
        draw();
      }
      function add(text) {
        var list = tags();
        text.split(",").map(function (t) { return t.trim(); }).filter(Boolean).forEach(function (tag) {
          var lower = tag.toLowerCase();
          if (!list.some(function (t) { return t.toLowerCase() === lower; })) list.push(tag);
        });
        entry.value = "";
        write(list);
      }
      function draw() {
        chips.innerHTML = "";
        tags().forEach(function (tag, i) {
          var li = document.createElement("li");
          li.appendChild(document.createTextNode(tag));
          var remove = document.createElement("button");
          remove.type = "button";
          remove.className = "lt-tag-remove";
          remove.textContent = "×";
          remove.setAttribute("aria-label", removeLabel.replace("~A", tag));
          remove.addEventListener("click", function () {
            var list = tags(); list.splice(i, 1); write(list); entry.focus();
          });
          li.appendChild(remove);
          chips.appendChild(li);
        });
      }
      entry.addEventListener("keydown", function (event) {
        if ((event.key === "Enter" || event.key === ",") && entry.value.trim()) {
          event.preventDefault();
          add(entry.value);
        } else if (event.key === "Backspace" && !entry.value) {
          var list = tags();
          if (list.length) { list.pop(); write(list); }
        }
      });
      entry.addEventListener("change", function () { if (entry.value.trim()) add(entry.value); });
      // What has been typed but not yet added goes with the form too.
      if (input.form) input.form.addEventListener("submit", function () {
        if (entry.value.trim()) add(entry.value);
      }, true);
      box.appendChild(chips);
      box.appendChild(entry);
      input.parentNode.insertBefore(box, input);
      draw();
    });
  }
  document.addEventListener("littoral:updated", function () { setupTags(); });

  // Dropdown menus (<details class="lt-dropdown">): one open at a time;
  // Escape or a click elsewhere closes them, and the arrow keys move
  // between their items.
  document.addEventListener("click", function (event) {
    document.querySelectorAll("details.lt-dropdown[open]").forEach(function (menu) {
      if (!menu.contains(event.target)) menu.removeAttribute("open");
    });
  });
  document.addEventListener("toggle", function (event) {
    var menu = event.target;
    if (!(menu.matches && menu.matches("details.lt-dropdown[open]"))) return;
    document.querySelectorAll("details.lt-dropdown[open]").forEach(function (other) {
      if (other !== menu && !other.contains(menu)) other.removeAttribute("open");
    });
  }, true);
  document.addEventListener("keydown", function (event) {
    var menu = event.target.closest ? event.target.closest("details.lt-dropdown") : null;
    if (!menu) return;
    var items = Array.prototype.slice.call(menu.querySelectorAll(
      ":scope > ul a, :scope > ul button, :scope > .lt-dropdown-panel a, :scope > .lt-dropdown-panel button"));
    var at = items.indexOf(document.activeElement);
    if (event.key === "Escape" && menu.open) {
      menu.removeAttribute("open");
      menu.querySelector("summary").focus();
    } else if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      if (!menu.open) menu.setAttribute("open", "");
      if (!items.length) return;
      var next = event.key === "ArrowDown" ? (at + 1) % items.length : (at <= 0 ? items.length - 1 : at - 1);
      items[next].focus();
    }
  });

  // File inputs: files can be dropped on them (or on the .lt-drop around
  // them), and a form sending files shows a progress bar while it uploads.
  function dropZone(target) {
    var zone = target.closest ? target.closest(".lt-drop") : null;
    return zone && zone.querySelector("input[type=file]") ? zone : null;
  }
  function carriesFiles(event) {
    return event.dataTransfer && Array.prototype.indexOf.call(event.dataTransfer.types, "Files") >= 0;
  }
  document.addEventListener("dragover", function (event) {
    var zone = dropZone(event.target);
    if (!zone || !carriesFiles(event)) return;
    event.preventDefault();
    zone.classList.add("lt-drop-over");
  });
  document.addEventListener("dragleave", function (event) {
    var zone = dropZone(event.target);
    if (zone && !zone.contains(event.relatedTarget)) zone.classList.remove("lt-drop-over");
  });
  document.addEventListener("drop", function (event) {
    var zone = dropZone(event.target);
    if (!zone || !carriesFiles(event)) return;
    event.preventDefault();
    zone.classList.remove("lt-drop-over");
    var input = zone.querySelector("input[type=file]");
    var files = new DataTransfer();
    Array.prototype.slice.call(event.dataTransfer.files, 0, input.multiple ? undefined : 1)
      .forEach(function (file) { files.items.add(file); });
    input.files = files.files;
    input.dispatchEvent(new Event("change", { bubbles: true }));
  });
  document.addEventListener("change", function (event) {
    var input = event.target;
    if (!(input.matches && input.matches("input[type=file]"))) return;
    var zone = input.closest(".lt-drop");
    var names = zone && zone.querySelector(".lt-drop-files");
    if (names) names.textContent = Array.prototype.map.call(input.files, function (f) { return f.name; }).join(", ");
  });
  document.addEventListener("submit", function (event) {
    var form = event.target;
    if (event.defaultPrevented || form.hasAttribute("data-lt-on-submit") || !window.XMLHttpRequest) return;
    var chosen = Array.prototype.some.call(form.querySelectorAll("input[type=file]"),
                                           function (input) { return input.files && input.files.length; });
    if (!chosen) return;
    event.preventDefault();
    var data = new FormData(form);
    // The button pressed names the callback to run, as in a plain submit.
    if (event.submitter && event.submitter.name) data.append(event.submitter.name, event.submitter.value);
    var bar = document.createElement("progress");
    bar.className = "lt-upload-progress";
    bar.max = 100;
    bar.value = 0;
    bar.setAttribute("aria-label", form.getAttribute("data-lt-uploading") || "Uploading");
    form.appendChild(bar);
    Array.prototype.forEach.call(form.querySelectorAll("button, input[type=submit]"), function (b) { b.disabled = true; });
    var xhr = new XMLHttpRequest();
    xhr.open("POST", form.action || window.location.href);
    xhr.upload.addEventListener("progress", function (e) {
      if (e.lengthComputable) bar.value = Math.round(100 * e.loaded / e.total);
    });
    xhr.addEventListener("load", function () {
      // Redirects were followed: the page the action led to.
      if (xhr.status < 400 && xhr.responseURL) window.location.href = xhr.responseURL;
      else { document.open(); document.write(xhr.responseText); document.close(); }
    });
    xhr.addEventListener("error", function () { form.submit(); });
    xhr.send(data);
  });

  // Lazy panels (data-lt-lazy): ask for their content once the page is
  // here, or, with data-lt-lazy-visible, once they're scrolled into view.
  function loadLazy(el) {
    if (el.hasAttribute("data-lt-lazy-sent")) return;
    el.setAttribute("data-lt-lazy-sent", "");
    trigger(el, "data-lt-lazy", null);
  }
  var lazyWatcher = window.IntersectionObserver ? new IntersectionObserver(function (entries) {
    entries.forEach(function (entry) {
      if (entry.isIntersecting) { lazyWatcher.unobserve(entry.target); loadLazy(entry.target); }
    });
  }) : null;
  function scanLazy() {
    document.querySelectorAll("[data-lt-lazy]:not([data-lt-lazy-sent])").forEach(function (el) {
      if (el.hasAttribute("data-lt-lazy-visible") && lazyWatcher) lazyWatcher.observe(el);
      else loadLazy(el);
    });
  }
  document.addEventListener("littoral:updated", scanLazy);

  // Command palettes (details.lt-palette): Ctrl-K or ⌘K opens the one with
  // the shortcut; the arrow keys go from the box through the results, Enter
  // in the box follows the first, and Escape or a click elsewhere closes it.
  var mac = /Mac|iPhone|iPad/.test(navigator.platform || navigator.userAgent);
  function setupPalettes() {
    if (mac) document.querySelectorAll(".lt-palette-key").forEach(function (key) { key.textContent = "⌘K"; });
  }
  function paletteLinks(palette) {
    return Array.prototype.slice.call(palette.querySelectorAll(".lt-palette-results a"));
  }
  function openPalette(palette) {
    palette.setAttribute("open", "");
    var box = palette.querySelector("input");
    if (box) { box.focus(); box.select(); }
  }
  document.addEventListener("keydown", function (event) {
    if ((event.ctrlKey || event.metaKey) && !event.altKey && (event.key === "k" || event.key === "K")) {
      var palette = document.querySelector("details.lt-palette[data-lt-palette=shortcut]");
      if (!palette) return;
      event.preventDefault();
      if (palette.open) palette.removeAttribute("open"); else openPalette(palette);
      return;
    }
    var within = event.target.closest ? event.target.closest("details.lt-palette") : null;
    if (!within) return;
    var links = paletteLinks(within);
    var at = links.indexOf(document.activeElement);
    var box = within.querySelector("input");
    if (event.key === "Escape") {
      event.preventDefault();
      within.removeAttribute("open");
      within.querySelector("summary").focus();
    } else if (event.key === "ArrowDown" && links.length) {
      event.preventDefault();
      links[at < 0 ? 0 : Math.min(at + 1, links.length - 1)].focus();
    } else if (event.key === "ArrowUp" && at >= 0) {
      event.preventDefault();
      if (at === 0) box.focus(); else links[at - 1].focus();
    } else if (event.key === "Enter" && event.target === box) {
      event.preventDefault();
      if (links.length) links[0].click();
    }
  });
  document.addEventListener("toggle", function (event) {
    var palette = event.target;
    if (!(palette.matches && palette.matches("details.lt-palette[open]"))) return;
    var box = palette.querySelector("input");
    if (box && document.activeElement !== box) box.focus();
  }, true);
  document.addEventListener("click", function (event) {
    document.querySelectorAll("details.lt-palette[open]").forEach(function (palette) {
      if (!palette.contains(event.target)) palette.removeAttribute("open");
    });
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
    setupTags();
    setupPalettes();
    scanLazy();
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
