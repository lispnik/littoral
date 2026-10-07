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
  function apply(data) {
    if (data.redirect) { window.location.href = data.redirect; return; }
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
  });

  // A page restored from the back/forward cache shows state the server may
  // have moved past (an isolated checkout, say), and Chrome restores even
  // no-store pages.  Ask the server again.
  window.addEventListener("pageshow", function (event) {
    if (event.persisted) window.location.reload();
  });
})();
