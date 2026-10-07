document.addEventListener("alpine:init", () => {
  window.Alpine.data("campaignTargets", () => ({
    ids: [],
    storeIds: [],
    stores: [],
    count: 0,
    summary: "",
    previewUrl: "",
    emptyText: "",
    seq: 0,

    init() {
      this.storeIds = JSON.parse(this.$el.dataset.storeIds || "[]").map(String)
      this.previewUrl = this.$el.dataset.previewUrl || ""
      this.emptyText = this.$el.dataset.emptyText || ""
      this.summary = this.emptyText
      this.$watch("ids", () => this.refresh())
    },

    selectAllStores() {
      this.ids = this.storeIds.slice()
    },

    clear() {
      this.ids = []
    },

    async refresh() {
      const seq = ++this.seq
      if (this.ids.length === 0) {
        this.stores = []
        this.count = 0
        this.summary = this.emptyText
        return
      }

      const params = new URLSearchParams()
      this.ids.forEach((id) => params.append("org_unit_ids[]", id))
      const response = await fetch(`${this.previewUrl}?${params}`, { headers: { Accept: "application/json" }, credentials: "same-origin" })
      if (!response.ok || seq !== this.seq) return

      const data = await response.json()
      if (seq !== this.seq) return
      this.stores = data.stores
      this.count = data.count
      this.summary = data.summary
    }
  }))
})
