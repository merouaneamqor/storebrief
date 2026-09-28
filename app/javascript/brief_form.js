document.addEventListener("alpine:init", () => {
  window.Alpine.data("briefForm", () => ({
    preview: false,
    settingsOpen: false,
    active: "title",
    titleFr: "",
    titleAr: "",
    bodyFr: "",
    bodyAr: "",
    format: "news",
    newsLabel: "",
    taskLabel: "",
    questions: [],
    activeQuestion: null,
    typeLabels: {},
    dragClientId: null,

    init() {
      this.titleFr = this.$el.dataset.titleFr || ""
      this.titleAr = this.$el.dataset.titleAr || ""
      this.bodyFr = this.$el.dataset.bodyFr || ""
      this.bodyAr = this.$el.dataset.bodyAr || ""
      this.format = this.$el.dataset.format || "news"
      this.newsLabel = this.$el.dataset.newsLabel || ""
      this.taskLabel = this.$el.dataset.taskLabel || ""
      this.typeLabels = JSON.parse(this.$el.dataset.typeLabels || "{}")
      this.questions = JSON.parse(this.$el.dataset.questions || "[]").map((question) => this.normalizeQuestion(question))
    },

    get formatLabel() {
      return this.format === "task" ? this.taskLabel : this.newsLabel
    },

    get visibleQuestions() {
      return this.questions.filter((question) => !question._destroy)
    },

    get headerTitle() {
      return this.titleFr.trim() || this.$el.dataset.untitled || "Untitled"
    },

    normalizeQuestion(question = {}) {
      const type = question.question_type || question.questionType || "short_text"
      const options = Array.isArray(question.options) && question.options.length
        ? question.options.map((option) => ({
          label_fr: option.label_fr || option.labelFr || "",
          label_ar: option.label_ar || option.labelAr || ""
        }))
        : [ { label_fr: "", label_ar: "" }, { label_fr: "", label_ar: "" } ]

      return {
        id: question.id || null,
        clientId: question.clientId || question.client_id || `q-${Date.now()}-${Math.random().toString(16).slice(2)}`,
        question_type: type,
        title_fr: question.title_fr || question.titleFr || "",
        title_ar: question.title_ar || question.titleAr || "",
        required: Boolean(question.required),
        options,
        _destroy: Boolean(question._destroy)
      }
    },

    focusTitle() {
      this.active = "title"
      this.activeQuestion = null
    },

    selectQuestion(clientId) {
      this.active = "question"
      this.activeQuestion = clientId
    },

    addQuestion() {
      const question = this.normalizeQuestion({ question_type: "short_text" })
      let insertAt = this.questions.length

      if (this.activeQuestion) {
        const index = this.questions.findIndex((item) => item.clientId === this.activeQuestion)
        if (index >= 0) insertAt = index + 1
      }

      this.questions.splice(insertAt, 0, question)
      this.active = "question"
      this.activeQuestion = question.clientId
      this.$nextTick(() => {
        const card = this.$root.querySelector(`[data-question-id="${question.clientId}"] .brief-question__title`)
        card?.focus()
      })
    },

    duplicateActive() {
      const current = this.questions.find((question) => question.clientId === this.activeQuestion && !question._destroy)
      if (!current) return

      const copy = this.normalizeQuestion({
        ...current,
        id: null,
        clientId: `q-${Date.now()}-${Math.random().toString(16).slice(2)}`,
        options: current.options.map((option) => ({ ...option })),
        _destroy: false
      })
      const index = this.questions.findIndex((question) => question.clientId === current.clientId)
      this.questions.splice(index + 1, 0, copy)
      this.activeQuestion = copy.clientId
    },

    deleteActive() {
      const current = this.questions.find((question) => question.clientId === this.activeQuestion && !question._destroy)
      if (!current) return

      if (current.id) {
        current._destroy = true
      } else {
        this.questions = this.questions.filter((question) => question.clientId !== current.clientId)
      }

      const next = this.visibleQuestions[0]
      this.activeQuestion = next ? next.clientId : null
      this.active = next ? "question" : "title"
    },

    moveActive(delta) {
      const visible = this.visibleQuestions
      const index = visible.findIndex((question) => question.clientId === this.activeQuestion)
      if (index < 0) return

      const target = index + delta
      if (target < 0 || target >= visible.length) return

      const fromId = visible[index].clientId
      const toId = visible[target].clientId
      const fromIndex = this.questions.findIndex((question) => question.clientId === fromId)
      const toIndex = this.questions.findIndex((question) => question.clientId === toId)
      const [ item ] = this.questions.splice(fromIndex, 1)
      this.questions.splice(toIndex, 0, item)
    },

    onDragStart(clientId, event) {
      this.dragClientId = clientId
      event.dataTransfer.effectAllowed = "move"
      event.dataTransfer.setData("text/plain", clientId)
    },

    onDragOver(event) {
      event.preventDefault()
      event.dataTransfer.dropEffect = "move"
    },

    onDrop(targetClientId, event) {
      event.preventDefault()
      const sourceId = this.dragClientId || event.dataTransfer.getData("text/plain")
      this.dragClientId = null
      if (!sourceId || sourceId === targetClientId) return

      const fromIndex = this.questions.findIndex((question) => question.clientId === sourceId)
      const toIndex = this.questions.findIndex((question) => question.clientId === targetClientId)
      if (fromIndex < 0 || toIndex < 0) return

      const [ item ] = this.questions.splice(fromIndex, 1)
      this.questions.splice(toIndex, 0, item)
      this.activeQuestion = sourceId
      this.active = "question"
    },

    needsOptions(type) {
      return [ "single_choice", "multi_choice", "dropdown" ].includes(type)
    },

    addOption(question) {
      question.options.push({ label_fr: "", label_ar: "" })
    },

    removeOption(question, index) {
      if (question.options.length <= 1) return
      question.options.splice(index, 1)
    },

    typeLabel(type) {
      return this.typeLabels[type] || type
    },

    openSettings() {
      this.settingsOpen = true
    },

    closeSettings() {
      this.settingsOpen = false
    }
  }))

  window.Alpine.data("briefTargets", () => ({
    units: [],
    selected: [],
    filter: "",
    type: "all",
    countTemplate: "",
    focused: false,

    init() {
      this.units = JSON.parse(this.$el.dataset.units || "[]").map((unit) => ({
        ...unit,
        id: String(unit.id)
      }))
      this.selected = JSON.parse(this.$el.dataset.selected || "[]").map(String)
      this.countTemplate = this.$el.dataset.countLabel || "%{count}"
    },

    get visible() {
      const query = this.filter.trim().toLowerCase()
      return this.units.filter((unit) => {
        const typeOk = this.type === "all" || unit.type === this.type
        const nameOk = query === "" || unit.name.toLowerCase().includes(query)
        return typeOk && nameOk
      })
    },

    get chosen() {
      return this.units.filter((unit) => this.selected.includes(unit.id))
    },

    get countLabel() {
      return this.countTemplate.replace("%{count}", String(this.selected.length))
    },

    toggle(id) {
      const key = String(id)
      if (this.selected.includes(key)) {
        this.selected = this.selected.filter((item) => item !== key)
      } else {
        this.selected = this.selected.concat([key])
      }
    },

    selectVisible() {
      const ids = new Set(this.selected)
      this.visible.forEach((unit) => ids.add(unit.id))
      this.selected = Array.from(ids)
    },

    clear() {
      this.selected = []
    }
  }))
})

document.addEventListener("turbo:load", () => {
  if (!window.Alpine) return

  document.querySelectorAll("[x-data]").forEach((el) => {
    if (el._x_dataStack) return
    if (el.parentElement && el.parentElement.closest("[x-data]")) return
    window.Alpine.initTree(el)
  })
})
