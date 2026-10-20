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
    } else if (el.type === "select-multiple") {
      // A blank first, as the field's hidden twin sends, so none is news too.
      params.append(el.name, "");
      Array.prototype.forEach.call(el.selectedOptions, function (o) { params.append(el.name, o.value); });
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

  // Where EL is within ROOT, to find its counterpart once ROOT is redrawn.
  function placeOf(root, el) {
    var path = [];
    for (var n = el; n !== root; n = n.parentElement)
      path.unshift(Array.prototype.indexOf.call(n.parentElement.children, n));
    return { path: path, tag: el.tagName, text: el.textContent };
  }
  function atPlace(root, place) {
    var n = root;
    for (var i = 0; n && i < place.path.length; i++) n = n.children[place.path[i]];
    return n && n.tagName === place.tag && n.textContent === place.text ? n : null;
  }

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
      // A region marked data-lt-keep-focus gives the focus back to the
      // same element when it has no id, as long as it's unchanged.
      var place = active && !focused && old.hasAttribute("data-lt-keep-focus") && old.contains(active)
        ? placeOf(old, active) : null;
      if (old.hasAttribute("aria-live")) {
        // Keep a live region's element, so screen readers announce the
        // change instead of losing the region.
        var holder = document.createElement("div");
        holder.innerHTML = data.fragments[id];
        var replacement = holder.firstElementChild;
        // Unchanged, it's left alone: rewriting it would announce it again.
        if (replacement && old.innerHTML !== replacement.innerHTML) {
          old.innerHTML = replacement.innerHTML;
          old.className = replacement.className;
        }
      } else {
        old.outerHTML = data.fragments[id];
      }
      // outerHTML drops focus; give it back, or honour autofocus.
      var fresh = document.getElementById(id);
      var target = (focused && fresh.querySelector("#" + CSS.escape(focused))) ||
                   fresh.querySelector("[autofocus]") || (place && atPlace(fresh, place));
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
    transport: function () { return socket && socket.readyState === 1 ? "websocket" : "fetch"; },
    // A new password's strength meter: the server's verdict on what was
    // typed, unless more has been typed since.
    strength: function (input, verdict) {
      var box = document.getElementById(input.id + "-strength");
      if (!box || !verdict || verdict.length !== input.value.length) return;
      box.hidden = !input.value;
      box.setAttribute("data-lt-score", verdict.score);
      box.querySelector("meter").value = verdict.score;
      box.querySelector(".lt-strength-text").textContent = verdict.text;
    }
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
    var box = palette.querySelector("input[type=search]");
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
    var box = within.querySelector("input[type=search]");
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
    var box = palette.querySelector("input[type=search]");
    if (box && document.activeElement !== box) box.focus();
  }, true);
  document.addEventListener("click", function (event) {
    document.querySelectorAll("details.lt-palette[open]").forEach(function (palette) {
      if (!palette.contains(event.target)) palette.removeAttribute("open");
    });
  });

  // Sliders (input[data-lt-range]): the number beside one follows it.
  // Colour fields (.lt-color): the picker and the code box follow each other.
  document.addEventListener("input", function (event) {
    var el = event.target;
    var output = el.getAttribute && el.getAttribute("data-lt-range");
    if (output) {
      var out = document.getElementById(output);
      if (out) out.textContent = el.value;
      return;
    }
    var box = el.closest ? el.closest(".lt-color") : null;
    if (!box) return;
    var picker = box.querySelector("input[type=color]"), code = box.querySelector(".lt-color-code");
    if (el === picker) {
      code.value = picker.value;
    } else if (el === code) {
      var v = code.value.trim();
      if (v && v.charAt(0) !== "#") v = "#" + v;
      if (/^#[0-9a-f]{3}$/i.test(v)) v = "#" + v[1] + v[1] + v[2] + v[2] + v[3] + v[3];
      if (/^#[0-9a-f]{6}$/i.test(v)) picker.value = v.toLowerCase();
    }
  });

  // Steppers (.lt-stepper): − and + change the number in place.
  document.addEventListener("click", function (event) {
    var button = event.target.closest ? event.target.closest(".lt-stepper [data-lt-step]") : null;
    var input = button && button.parentNode.querySelector("input[type=number]");
    if (!input) return;
    event.preventDefault();
    try {
      if (+button.getAttribute("data-lt-step") > 0) input.stepUp(); else input.stepDown();
    } catch (e) { return; }
    input.dispatchEvent(new Event("input", { bubbles: true }));
    input.dispatchEvent(new Event("change", { bubbles: true }));
  });

  // Transfer lists (.lt-transfer): the buttons, or a double click, move the
  // selected items across in place, in the choices' order; the hidden field
  // carries what is chosen.
  function transferMove(box, toChosen) {
    var source = box.querySelector(toChosen ? ".lt-transfer-available" : ".lt-transfer-chosen");
    var target = box.querySelector(toChosen ? ".lt-transfer-chosen" : ".lt-transfer-available");
    var moving = Array.prototype.filter.call(source.options, function (o) { return o.selected; });
    moving.forEach(function (o) {
      o.selected = false;
      var before = Array.prototype.filter.call(target.options, function (t) { return +t.value > +o.value; })[0];
      target.insertBefore(o, before || null);
    });
    box.querySelector(".lt-transfer-value").value =
      Array.prototype.map.call(box.querySelector(".lt-transfer-chosen").options, function (o) { return o.value; }).join(",");
    var status = box.querySelector(".lt-transfer-status");
    var heading = box.querySelector("label[for='" + target.id + "']");
    if (status && moving.length && heading)
      status.textContent = heading.textContent + ": " + moving.map(function (o) { return o.textContent; }).join(", ");
  }
  document.addEventListener("click", function (event) {
    var button = event.target.closest ? event.target.closest(".lt-transfer [data-lt-move]") : null;
    if (!button) return;
    event.preventDefault();
    transferMove(button.closest(".lt-transfer"), button.getAttribute("data-lt-move") === "add");
  });
  document.addEventListener("dblclick", function (event) {
    var option = event.target.closest ? event.target.closest(".lt-transfer option") : null;
    if (!option) return;
    Array.prototype.forEach.call(option.parentNode.options, function (o) { o.selected = o === option; });
    transferMove(option.closest(".lt-transfer"), option.parentNode.classList.contains("lt-transfer-available"));
  });

  // Tooltips (.lt-tooltip): the tip describes the first thing inside that
  // takes the focus, or the wrapper, made focusable; Escape hides it until
  // the pointer or the focus leaves.
  function setupTooltips() {
    document.querySelectorAll(".lt-tooltip:not([data-lt-tooltip-ready])").forEach(function (wrap) {
      var tip = wrap.querySelector(".lt-tooltip-text");
      if (!tip) return;
      wrap.setAttribute("data-lt-tooltip-ready", "");
      var target = wrap.querySelector("a[href], button, input, select, textarea, [tabindex]");
      if (!target) { target = wrap; wrap.tabIndex = 0; }
      var ids = (target.getAttribute("aria-describedby") || "").split(/\s+/).filter(Boolean);
      if (ids.indexOf(tip.id) < 0) ids.push(tip.id);
      target.setAttribute("aria-describedby", ids.join(" "));
    });
  }
  document.addEventListener("littoral:updated", setupTooltips);
  document.addEventListener("keydown", function (event) {
    if (event.key !== "Escape") return;
    document.querySelectorAll(".lt-tooltip:hover, .lt-tooltip:focus-within").forEach(function (wrap) {
      wrap.classList.add("lt-tooltip-dismissed");
    });
  });
  function undismiss(event) {
    var wrap = event.target.closest ? event.target.closest(".lt-tooltip-dismissed") : null;
    if (wrap && !wrap.contains(event.relatedTarget)) wrap.classList.remove("lt-tooltip-dismissed");
  }
  document.addEventListener("focusout", undismiss);
  document.addEventListener("mouseout", undismiss);

  // Popovers (.lt-popover): placed below their button (above, when there's
  // no room below), within the window.
  document.addEventListener("toggle", function (event) {
    var pop = event.target;
    if (!(pop.matches && pop.matches(".lt-popover")) || event.newState !== "open") return;
    var button = document.querySelector("[popovertarget='" + pop.id + "']");
    if (!button) return;
    var r = button.getBoundingClientRect();
    pop.style.position = "fixed";
    pop.style.inset = "auto";
    pop.style.margin = "0";
    var left = Math.max(8, Math.min(r.left, window.innerWidth - pop.offsetWidth - 8));
    var top = r.bottom + 6;
    if (top + pop.offsetHeight > window.innerHeight - 8 && r.top - pop.offsetHeight - 6 >= 8)
      top = r.top - pop.offsetHeight - 6;
    pop.style.left = left + "px";
    pop.style.top = top + "px";
  }, true);

  // Drawers (.lt-drawer): Escape or a click outside closes one, and the
  // focus goes back to its button.  (Opening, the close link has autofocus.)
  function closeDrawer(drawer) {
    var close = drawer.querySelector(".lt-drawer-close");
    if (close) close.click();
  }
  document.addEventListener("keydown", function (event) {
    if (event.key !== "Escape" || event.defaultPrevented) return;
    var drawer = document.querySelector(".lt-drawer");
    if (!drawer) return;
    var active = document.activeElement;
    if (active && active !== document.body && !drawer.parentNode.contains(active)) return;
    event.preventDefault();
    closeDrawer(drawer);
  });
  document.addEventListener("click", function (event) {
    document.querySelectorAll(".lt-drawer").forEach(function (drawer) {
      if (!drawer.contains(event.target) && !drawer.parentNode.contains(event.target)) closeDrawer(drawer);
      else if (event.target.classList && event.target.classList.contains("lt-drawer-backdrop")) closeDrawer(drawer);
    });
  });
  document.addEventListener("littoral:updated", function (event) {
    ((event.detail && event.detail.ids) || []).forEach(function (id) {
      var wrapper = document.getElementById(id);
      var toggle = wrapper && wrapper.querySelector(":scope > .lt-drawer-toggle");
      var active = document.activeElement;
      if (toggle && toggle.getAttribute("aria-expanded") === "false" && (!active || active === document.body))
        toggle.focus();
    });
  });

  // Split panes (.lt-split): drag the divider, or focus it and use the
  // arrow keys (Shift for bigger steps; Home and End for the limits).  The
  // new share is posted once the move ends.
  function splitSet(divider, percent) {
    var min = +divider.getAttribute("aria-valuemin"), max = +divider.getAttribute("aria-valuemax");
    var value = Math.round(Math.max(min, Math.min(max, percent)));
    divider.setAttribute("aria-valuenow", value);
    divider.setAttribute("aria-valuetext", value + "%");
    divider.parentNode.style.setProperty("--lt-split", value + "%");
  }
  document.addEventListener("pointerdown", function (event) {
    var divider = event.target.closest ? event.target.closest(".lt-split-divider") : null;
    if (!divider || event.button !== 0) return;
    event.preventDefault();
    divider.focus();
    var split = divider.parentNode;
    split.classList.add("lt-split-dragging");
    try { divider.setPointerCapture(event.pointerId); } catch (e) {}
    function move(e) {
      var r = split.getBoundingClientRect();
      splitSet(divider, 100 * (e.clientX - r.left) / r.width);
    }
    function up() {
      divider.removeEventListener("pointermove", move);
      divider.removeEventListener("pointerup", up);
      divider.removeEventListener("pointercancel", up);
      split.classList.remove("lt-split-dragging");
      trigger(divider, "data-lt-split", null);
    }
    divider.addEventListener("pointermove", move);
    divider.addEventListener("pointerup", up);
    divider.addEventListener("pointercancel", up);
  });
  document.addEventListener("keydown", function (event) {
    var divider = event.target.closest ? event.target.closest(".lt-split-divider") : null;
    if (!divider) return;
    var now = +divider.getAttribute("aria-valuenow"), step = event.shiftKey ? 10 : 2;
    var to = { ArrowLeft: now - step, ArrowRight: now + step, Home: -Infinity, End: Infinity }[event.key];
    if (to === undefined) return;
    event.preventDefault();
    splitSet(divider, to);
    clearTimeout(divider.ltSave);
    divider.ltSave = setTimeout(function () { trigger(divider, "data-lt-split", null); }, 400);
  });

  // Virtual grids (.lt-grid-virtual): as the box scrolls, ask for the rows
  // around those on screen.  Spacers stand for the rest, at the measured
  // row height, so the scroll bar is right.
  function virtualRowHeight(box) {
    var row = box.querySelector("tbody.lt-grid-rows > tr:not(.lt-grid-spacer):not(.lt-grid-editing)");
    return row ? row.getBoundingClientRect().height : 0;
  }
  function virtualCheck(box) {
    var spacer = box.querySelector("tr.lt-grid-spacer[data-lt-virtual]");
    var h = virtualRowHeight(box);
    if (!spacer || !h || box.ltAsking) return;
    var start = +spacer.getAttribute("data-lt-start"), total = +spacer.getAttribute("data-lt-total");
    var size = +spacer.getAttribute("data-lt-window"), visible = +spacer.getAttribute("data-lt-visible");
    var end = Math.min(total, start + size), first = Math.floor(box.scrollTop / h);
    var margin = Math.floor(visible / 2);
    if ((start > 0 && first - margin < start) || (end < total && first + visible + margin > end)) {
      var want = Math.max(0, Math.min(total - size, first - visible));
      if (want === start) return;
      spacer.setAttribute("data-lt-want", want);
      box.ltAsking = true;
      trigger(spacer, "data-lt-virtual", null);
    }
  }
  function setupVirtual() {
    document.querySelectorAll(".lt-grid-virtual").forEach(function (box) {
      box.ltAsking = false;
      var h = virtualRowHeight(box);
      if (h) box.style.setProperty("--lt-grid-row", h + "px");
      if (!box.hasAttribute("data-lt-placed")) {
        // Back where it was left, when the page comes again.
        box.setAttribute("data-lt-placed", "");
        var spacer = box.querySelector("tr.lt-grid-spacer[data-lt-virtual]");
        var start = spacer ? +spacer.getAttribute("data-lt-start") : 0;
        if (start > 0 && h) box.scrollTop = (start + +spacer.getAttribute("data-lt-visible")) * h;
      }
      virtualCheck(box);
    });
  }
  document.addEventListener("scroll", function (event) {
    var box = event.target;
    if (!box.classList || !box.classList.contains("lt-grid-virtual") || box.ltFrame) return;
    box.ltFrame = requestAnimationFrame(function () { box.ltFrame = 0; virtualCheck(box); });
  }, true);
  document.addEventListener("littoral:updated", setupVirtual);

  // Event calendars (.lt-schedule): drag an event to another time or day.
  // The new start is posted when it is dropped; a plain click chooses it.
  function pad2(n) { return (n < 10 ? "0" : "") + n; }
  document.addEventListener("pointerdown", function (event) {
    var link = event.target.closest ? event.target.closest(".lt-schedule-event-link[data-lt-move]") : null;
    if (!link || event.button !== 0) return;
    var item = link.parentNode, grid = link.closest(".lt-schedule-grid");
    var step = +grid.getAttribute("data-lt-step"), first = +grid.getAttribute("data-lt-first");
    var slots = +grid.getAttribute("data-lt-slots");
    var span = parseFloat(item.style.getPropertyValue("--lt-span")) || 1;
    var grab = event.clientY - item.getBoundingClientRect().top;
    var x0 = event.clientX, y0 = event.clientY, dragging = false, day = null, slot = 0;
    function dayAt(x) {
      return Array.prototype.filter.call(grid.querySelectorAll(".lt-schedule-day"), function (d) {
        var r = d.getBoundingClientRect();
        return x >= r.left && x < r.right;
      })[0];
    }
    function move(e) {
      if (!dragging && Math.abs(e.clientX - x0) + Math.abs(e.clientY - y0) < 6) return;
      if (!dragging) {
        dragging = true;
        item.classList.add("lt-dragging");
        try { link.setPointerCapture(e.pointerId); } catch (x) {}
      }
      day = dayAt(e.clientX) || day || item.closest(".lt-schedule-day");
      var box = day.querySelector(".lt-schedule-slots"), r = box.getBoundingClientRect();
      slot = Math.max(0, Math.min(slots - Math.min(span, slots), Math.round((e.clientY - grab - r.top) / (r.height / slots))));
      var list = box.querySelector(".lt-schedule-events");
      if (!list) { list = document.createElement("ol"); list.className = "lt-schedule-events"; box.appendChild(list); }
      if (item.parentNode !== list) list.appendChild(item);
      item.style.setProperty("--lt-from", slot);
      item.style.setProperty("--lt-col", 0);
      item.style.setProperty("--lt-cols", 1);
    }
    function up() {
      document.removeEventListener("pointermove", move);
      document.removeEventListener("pointerup", up);
      document.removeEventListener("pointercancel", up);
      if (!dragging) return;
      item.classList.remove("lt-dragging");
      link.ltDragged = Date.now();
      var minutes = first + slot * step;
      link.setAttribute("data-lt-to", day.getAttribute("data-lt-day") + " " + pad2(Math.floor(minutes / 60)) + ":" + pad2(minutes % 60));
      trigger(link, "data-lt-move", null);
    }
    document.addEventListener("pointermove", move);
    document.addEventListener("pointerup", up);
    document.addEventListener("pointercancel", up);
  });
  // A drag ends in a click; it mustn't choose the event too.
  document.addEventListener("click", function (event) {
    var link = event.target.closest ? event.target.closest(".lt-schedule-event-link") : null;
    if (link && link.ltDragged && Date.now() - link.ltDragged < 500) {
      event.preventDefault();
      event.stopPropagation();
    }
  }, true);

  // Relative times (time[data-lt-relative]): "3 minutes ago", kept up to
  // date in the page's language.  Under a minute it's the server's "just
  // now"; after a week, the date it gave.
  var relativeFormat;
  function relativeText(el) {
    var seconds = Math.max(0, (Date.now() - Date.parse(el.getAttribute("datetime"))) / 1000);
    if (isNaN(seconds)) return null;
    if (seconds < 60) return el.getAttribute("data-lt-now");
    if (seconds >= 7 * 86400) return el.getAttribute("data-lt-date");
    if (relativeFormat === undefined) {
      try { relativeFormat = new Intl.RelativeTimeFormat(document.documentElement.lang || undefined, { numeric: "always" }); }
      catch (e) { relativeFormat = null; }
    }
    if (!relativeFormat) return null;
    if (seconds < 3600) return relativeFormat.format(-Math.floor(seconds / 60), "minute");
    if (seconds < 86400) return relativeFormat.format(-Math.floor(seconds / 3600), "hour");
    return relativeFormat.format(-Math.floor(seconds / 86400), "day");
  }
  function updateRelativeTimes() {
    document.querySelectorAll("time[data-lt-relative]").forEach(function (el) {
      var words = relativeText(el);
      if (words && el.textContent !== words) el.textContent = words;
    });
  }
  setInterval(updateRelativeTimes, 30000);
  document.addEventListener("littoral:updated", updateRelativeTimes);

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
    setupTooltips();
    setupVirtual();
    updateRelativeTimes();
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
