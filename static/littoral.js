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

  function post(callback, targets, params, el, attr) {
    params.append("_lt_ajax", "1");
    params.append("_lt_update", targets);
    if (callback) params.append(callback, "1");
    return fetch(actionUrl(), {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: params.toString(),
      credentials: "same-origin"
    })
      .then(function (r) {
        if (!r.ok) throw new Error("HTTP " + r.status);
        return r.json();
      })
      .then(function (data) {
        apply(data);
        var complete = el && attr && el.getAttribute(attr + "-complete");
        if (complete) new Function("value", complete).call(el, data.value);
      })
      .catch(function () { window.location.reload(); });
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

  function apply(data) {
    if (data.redirect) { window.location.href = data.redirect; return; }
    showToasts(data.toasts);
    var focused = document.activeElement && document.activeElement.id;
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
    });
    if (data.missing.length) window.location.reload();
    (data.scripts || []).forEach(function (script) { new Function(script)(); });
    scanPeriodicals();
    document.dispatchEvent(new CustomEvent("littoral:updated",
      { detail: { ids: Object.keys(data.fragments) } }));
  }

  // Server push: pages showing subscribed components listen for updates.
  function listen() {
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
      var value = new Function("return (" + valueExpression + ");").call(el);
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
      if (el) new Function("event", el.getAttribute(attr)).call(el, event);
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
      return fetch(actionUrl(), {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: params.toString(), credentials: "same-origin"
      }).then(function (r) { return r.json(); })
        .then(function (data) { apply(data); return data.value; });
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
