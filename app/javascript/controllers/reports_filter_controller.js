import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "query", "row", "empty", "chip" ]
  static values = { filter: { type: String, default: "all" } }

  connect() {
    this.apply()
  }

  setFilter(event) {
    this.filterValue = event.currentTarget.dataset.filter
    this.chipTargets.forEach((chip) => {
      const active = chip.dataset.filter === this.filterValue
      chip.classList.toggle("is-active", active)
      chip.setAttribute("aria-pressed", active ? "true" : "false")
    })
    this.apply()
  }

  apply() {
    const query = this.hasQueryTarget ? this.queryTarget.value.trim().toLowerCase() : ""
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
