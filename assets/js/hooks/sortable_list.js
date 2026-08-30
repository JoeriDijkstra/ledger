// LiveView hook: drag-to-reorder a list using the native HTML5
// drag-and-drop API (no external dependency). Attach to the list container;
// each draggable child must carry data-sortable-id. While dragging we
// reorder the DOM optimistically for live feedback, and on drop we push the
// resulting id order to the server via the configured event.
//
//   <ul id="..." phx-hook="SortableList" data-sortable-event="reorder_previews">
//     <li draggable="true" data-sortable-id={id} id={"row-#{id}"}>…</li>
//
// Vertical by default; data-sortable-axis="x" sorts a horizontal strip.
//
// Listeners are delegated on the container and attached once in mounted(),
// so they survive LiveView patches (which keep the same container element).
export const SortableList = {
  mounted() {
    this.dragEl = null
    this.horizontal = this.el.dataset.sortableAxis === "x"
    const el = this.el
    const event = el.dataset.sortableEvent || "reorder"

    el.addEventListener("dragstart", (e) => {
      const li = e.target.closest("[data-sortable-id]")
      if (!li) return
      this.dragEl = li
      li.classList.add("is-dragging")
      e.dataTransfer.effectAllowed = "move"
    })

    el.addEventListener("dragend", () => {
      if (this.dragEl) this.dragEl.classList.remove("is-dragging")
      this.dragEl = null
    })

    el.addEventListener("dragover", (e) => {
      if (!this.dragEl) return
      e.preventDefault()
      e.dataTransfer.dropEffect = "move"
      const after = this.afterElement(this.horizontal ? e.clientX : e.clientY)
      if (after == null) {
        el.appendChild(this.dragEl)
      } else if (after !== this.dragEl) {
        el.insertBefore(this.dragEl, after)
      }
    })

    el.addEventListener("drop", (e) => {
      e.preventDefault()
      const ids = [...el.querySelectorAll("[data-sortable-id]")].map((li) => li.dataset.sortableId)
      // `key` lets a handler tell which list reordered when several share the
      // event name; omitted (undefined) for single-list users like previews.
      this.pushEvent(event, {ids, key: el.dataset.sortableKey})
    })
  },

  // The first sibling whose midpoint lies past the cursor along the sort
  // axis — the dragged element should be inserted before it.
  afterElement(pos) {
    const items = [...this.el.querySelectorAll("[data-sortable-id]:not(.is-dragging)")]
    return items.reduce(
      (closest, child) => {
        const box = child.getBoundingClientRect()
        const offset = this.horizontal
          ? pos - box.left - box.width / 2
          : pos - box.top - box.height / 2
        if (offset < 0 && offset > closest.offset) {
          return {offset, element: child}
        }
        return closest
      },
      {offset: Number.NEGATIVE_INFINITY, element: null}
    ).element
  },
}
