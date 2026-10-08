import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "stores", "workload" ]
  static values = {
    stores: Array,
    workload: Object,
    labels: Object
  }

  connect() {
    if (!window.Chart) return

    const accent = cssVar("--accent", "#166534")
    const secondary = cssVar("--secondary", "#ca8a04")
    const legend = { position: "bottom", labels: { boxWidth: 10, boxHeight: 10, padding: 14, usePointStyle: true } }
    window.Chart.defaults.font.family = getComputedStyle(document.body).fontFamily
    window.Chart.defaults.color = cssVar("--muted", "#57534e")

    this.charts = []

    if (this.hasStoresTarget) {
      this.charts.push(new window.Chart(this.storesTarget, {
        type: "doughnut",
        data: {
          labels: [ this.labelsValue.clear, this.labelsValue.behind ],
          datasets: [ {
            data: this.storesValue,
            backgroundColor: [ accent, secondary ],
            borderWidth: 0
          } ]
        },
        options: {
          responsive: true,
          maintainAspectRatio: true,
          cutout: "68%",
          plugins: { legend: legend }
        }
      }))
    }

    const names = this.workloadValue.names || []
    if (this.hasWorkloadTarget && names.length) {
      this.charts.push(new window.Chart(this.workloadTarget, {
        type: "bar",
        data: {
          labels: this.workloadValue.names,
          datasets: [
            { label: this.labelsValue.briefs, data: this.workloadValue.briefs, backgroundColor: accent, borderRadius: 6, maxBarThickness: 42 },
            { label: this.labelsValue.checks, data: this.workloadValue.checks, backgroundColor: secondary, borderRadius: 6, maxBarThickness: 42 }
          ]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          scales: {
            x: { stacked: true, grid: { display: false } },
            y: { stacked: true, beginAtZero: true, ticks: { precision: 0 } }
          },
          plugins: { legend: legend }
        }
      }))
    }
  }

  disconnect() {
    this.charts?.forEach((chart) => chart.destroy())
  }
}

function cssVar(name, fallback) {
  const value = getComputedStyle(document.body).getPropertyValue(name).trim()
  return value || fallback
}
