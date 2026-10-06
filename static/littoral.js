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

  function post(callback, targets, params) {
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
        Object.keys(data.fragments).forEach(function (id) {
          var old = document.getElementById(id);
          if (old) old.outerHTML = data.fragments[id];
        });
        if (data.missing.length) window.location.reload();
        scanPeriodicals();
      })
      .catch(function () { window.location.reload(); });
  }

  function split(spec) {
    var i = spec.indexOf(";");
    return { callback: spec.slice(0, i), targets: spec.slice(i + 1) };
  }

  function trigger(el, attr, event) {
    var spec = split(el.getAttribute(attr));
    var params = new URLSearchParams();
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
    post(spec.callback, spec.targets, params);
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

  document.addEventListener("DOMContentLoaded", scanPeriodicals);
})();
