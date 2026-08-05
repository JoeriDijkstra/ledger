// Client-side half of the command palette: it remembers what you opened, and
// keeps the keyboard cursor on screen.
//
// ## Recents
//
// Recents are per-browser, not per-account, so they live in localStorage
// rather than the database — there is nothing here worth a table, and a
// round trip on every palette open would be worse than the feature.
//
// The server never trusts what comes back: it re-checks that each path
// belongs to the current site before rendering it as a link.
const KEY = "masthead:palette-recents"
const MAX = 5

function read() {
  try {
    const items = JSON.parse(window.localStorage.getItem(KEY) || "[]")
    return Array.isArray(items) ? items.filter(isEntry).slice(0, MAX) : []
  } catch (_e) {
    // Private mode, quota, or someone else's malformed value — recents are
    // a convenience, so degrade to "none" rather than breaking the palette.
    return []
  }
}

function isEntry(e) {
  return e && typeof e.label === "string" && typeof e.path === "string"
}

function write(items) {
  try {
    window.localStorage.setItem(KEY, JSON.stringify(items.slice(0, MAX)))
  } catch (_e) {
    // Nothing to do — the palette works fine without a memory.
  }
}

function record(entry) {
  if (!isEntry(entry)) return
  // Most recent first, and one row per destination.
  const rest = read().filter(e => e.path !== entry.path)
  write([{label: entry.label, meta: entry.meta || "", path: entry.path}, ...rest])
}

export const CommandPalette = {
  mounted() {
    this.send()

    // Mouse clicks navigate through the anchor itself and never reach the
    // server, so record them here. Keyboard selection goes through the
    // server, which echoes back a "palette:record" event.
    // `data-record` is absent on commands and destinations: those are always
    // on screen anyway, so remembering them would only duplicate a row.
    this.onClick = e => {
      const item = e.target.closest(".palette-item")
      if (!item || item.dataset.record !== "1") return
      record({
        label: item.dataset.label,
        meta: item.dataset.meta,
        path: item.getAttribute("href")
      })
    }
    this.el.addEventListener("click", this.onClick)

    this.handleEvent("palette:record", entry => {
      record(entry)
      this.send()
    })
  },

  // The cursor lives on the server, so the row it lands on can be scrolled
  // out of sight in the results list. Pull it back into view after each
  // patch. "nearest" scrolls the list only — never the page behind it — and
  // does nothing when the row is already visible.
  updated() {
    const active = this.el.querySelector(".palette-item.is-active")
    if (active) active.scrollIntoView({block: "nearest"})
  },

  destroyed() {
    this.el.removeEventListener("click", this.onClick)
  },

  send() {
    this.pushEventTo(this.el, "recents", {items: read()})
  }
}
