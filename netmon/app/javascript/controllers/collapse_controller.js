import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content", "icon"]

  connect() {
    this.storageKey = this.element.dataset.collapseStorageKey || "netmon.filterbar.collapsed"
    const stored = window.localStorage.getItem(this.storageKey)
    const collapsed = stored === "true"
    this.setCollapsed(collapsed)
  }

  toggle() {
    const collapsed = !this.contentTarget.classList.contains("hidden")
    this.setCollapsed(collapsed)
  }

  setCollapsed(collapsed) {
    if (collapsed) {
      this.contentTarget.classList.add("hidden")
    } else {
      this.contentTarget.classList.remove("hidden")
    }
    window.localStorage.setItem(this.storageKey, String(collapsed))
    if (this.hasIconTarget) {
      this.iconTarget.textContent = collapsed ? "▸" : "▾"
    }
  }
}
