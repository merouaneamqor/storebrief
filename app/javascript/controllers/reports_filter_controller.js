import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "query", "row", "empty", "chip", "download" ]
  static values = { filter: { type: String, default: "all" } }

  connect() {
    this.updateChips()
    this.apply()
  }

  setFilter(event) {
    this.filterValue = event.currentTarget.dataset.filter
    this.updateChips()
    this.apply()
  }

  updateChips() {
    this.chipTargets.forEach((chip) => {
      const active = chip.dataset.filter === this.filterValue
      chip.classList.toggle("is-active", active)
      chip.setAttribute("aria-pressed", active ? "true" : "false")
    })
  }

  apply() {
    const query = this.hasQueryTarget ? this.queryTarget.value.trim().toLowerCase() : ""
    this.downloadTargets.forEach((link) => {
      const url = new URL(link.href)
      url.searchParams.set("query", query)
      url.searchParams.set("state", this.filterValue)
      link.href = url.toString()
    })
    let visible = 0

    this.rowTargets.forEach((row) => {
      const matchesFilter = this.filterValue === "all" || row.dataset.state === this.filterValue
      const matchesQuery = query === "" || (row.dataset.search || "").includes(query)
      const show = matchesFilter && matchesQuery
      row.hidden = !show
      if (show) visible += 1
    })

    if (this.hasEmptyTarget) this.emptyTarget.hidden = visible !== 0
  }
}
