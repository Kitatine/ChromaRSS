(() => {
  if (window.top !== window || window.__chromaHelperLoaded) return;
  window.__chromaHelperLoaded = true;

  let pill = null;
  let active = false;

  function translateURL(text) {
    return "https://translate.google.com/?sl=auto&tl=en&op=translate&text=" + encodeURIComponent(text.slice(0, 1500));
  }

  function setActive(on) {
    active = on;
    document.documentElement.classList.toggle("chroma-bilingual-on", on);
    if (pill) pill.classList.toggle("chroma-on", on);
    if (!on) document.querySelectorAll(".chroma-callout").forEach((n) => n.remove());
  }

  function onParagraphTap(event) {
    if (!active) return;
    const p = event.target.closest && event.target.closest("p, li, blockquote, h1, h2, h3");
    if (!p || p.closest(".chroma-callout") || p.closest(".chroma-pill")) return;
    const text = (p.innerText || "").trim();
    if (text.length < 4) return;
    if (p.nextElementSibling && p.nextElementSibling.classList.contains("chroma-callout")) {
      p.nextElementSibling.remove();
      return;
    }
    const box = document.createElement("div");
    box.className = "chroma-callout";
    const link = document.createElement("a");
    link.href = translateURL(text);
    link.target = "_blank";
    link.textContent = "Translate this paragraph";
    box.append("文A  ", link);
    p.insertAdjacentElement("afterend", box);
  }

  function createPill() {
    if (pill) return;
    pill = document.createElement("button");
    pill.className = "chroma-pill";
    pill.type = "button";
    pill.textContent = "文A";
    pill.addEventListener("click", () => setActive(!active));
    document.documentElement.appendChild(pill);
  }

  function removePill() {
    if (pill) pill.remove();
    pill = null;
    setActive(false);
  }

  document.addEventListener("click", onParagraphTap, true);

  chrome.storage.local.get({ showPill: true }, (v) => { if (v.showPill) createPill(); });
  chrome.storage.onChanged.addListener((changes) => {
    if (changes.showPill) changes.showPill.newValue ? createPill() : removePill();
  });
  chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (message && message.type === "toggleBilingualDemo") {
      setActive(!active);
      sendResponse({ active });
    } else if (message && message.type === "getStatus") {
      sendResponse({ active, hasPill: !!pill });
    }
    return true;
  });
})();
