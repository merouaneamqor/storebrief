document.addEventListener("alpine:init", () => {
  window.Alpine.data("auditTemplateForm", () => ({
    sections: [],

    init() {
      const parsed = JSON.parse(this.$el.dataset.sections || "[]")
      this.sections = parsed.length ? parsed : [ this.blankSection() ]
    },

    blankSection() {
      return { key: `s${this.sections.length + 1}`, title_fr: "", title_ar: "", questions: [ this.blankQuestion(1) ] }
    },

    blankQuestion(index) {
      return {
        key: `q${index}`,
        prompt_fr: "",
        prompt_ar: "",
        required: true,
        kind: "verdict",
        points: 1,
        show_if_key: "",
        show_if_value: ""
      }
    },

    addSection() {
      this.sections.push(this.blankSection())
    },

    addQuestion(section) {
      section.questions.push(this.blankQuestion(section.questions.length + 1))
    },

    removeQuestion(section, index) {
      section.questions.splice(index, 1)
    },

    removeSection(index) {
      if (this.sections.length === 1) return
      this.sections.splice(index, 1)
    }
  }))
})
