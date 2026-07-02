// Wire each <andypf-json-viewer data-src="ID"> to the JSON in the sibling
// <script type="application/json" id="ID"> tag, and keep its theme in sync with
// Quarto's light/dark toggle. Keeping the payload in a script tag (rather than a
// giant `data` attribute) keeps the generated HTML clean and avoids escaping bugs.
(function () {
  function currentTheme() {
    // Quarto sets `.quarto-light` / `.quarto-dark` on <body>.
    return document.body.classList.contains("quarto-dark") ? "default-dark" : "default-light";
  }

  function hydrate() {
    var theme = currentTheme();
    document.querySelectorAll("andypf-json-viewer[data-src]").forEach(function (el) {
      var src = document.getElementById(el.getAttribute("data-src"));
      if (src) {
        try {
          el.data = JSON.parse(src.textContent);
        } catch (e) {
          console.error("[amr] could not parse JSON for", el.getAttribute("data-src"), e);
        }
      }
      el.setAttribute("theme", theme);
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", hydrate);
  } else {
    hydrate();
  }

  // Re-theme when the user flips Quarto's toggle (it mutates the body class list).
  var obs = new MutationObserver(function () {
    var theme = currentTheme();
    document.querySelectorAll("andypf-json-viewer").forEach(function (el) {
      el.setAttribute("theme", theme);
    });
  });
  obs.observe(document.body, { attributes: true, attributeFilter: ["class"] });
})();
