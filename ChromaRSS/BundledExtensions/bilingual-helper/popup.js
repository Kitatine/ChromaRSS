const pill = document.getElementById("pill");
const toggle = document.getElementById("toggle");
const status = document.getElementById("status");

chrome.storage.local.get({ showPill: true }, (v) => { pill.checked = v.showPill; });
pill.addEventListener("change", () => chrome.storage.local.set({ showPill: pill.checked }));

toggle.addEventListener("click", async () => {
  try {
    const tabs = await chrome.tabs.query({ active: true, currentWindow: true });
    if (!tabs.length) { status.textContent = "No active tab."; return; }
    const reply = await chrome.tabs.sendMessage(tabs[0].id, { type: "toggleBilingualDemo" });
    status.textContent = reply && reply.active ? "Preview on: tap a paragraph." : "Preview off.";
  } catch (e) {
    status.textContent = "Couldn't reach this page: " + e.message;
  }
});
