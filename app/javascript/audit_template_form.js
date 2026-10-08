document.addEventListener("alpine:init", () => {
  window.Alpine.data("auditTemplateForm", () => ({
    sections: [],

    init() {
      const parsed = JSON.parse(this.$el.dataset.sections || "[]")
      this.sections = parsed.length ? parsed : [ this.blankSection() ]
    },

    takenKeys() {
      const keys = []
      for (const section of this.sections) {
        if (section.key) keys.push(section.key)
        for (const question of section.questions || []) {
          if (question.key) keys.push(question.key)
          if (question.show_if_key) keys.push(question.show_if_key)
        }
      }
      return new Set(keys)
    },

    freshKey(prefix) {
      const taken = this.takenKeys()
      let index = 1
      let key = `${prefix}${index}`
      while (taken.has(key)) {
        index += 1
        key = `${prefix}${index}`
      }
      return key
    },

    blankSection() {
      return {
        key: this.freshKey("s"),
        title_fr: "",
        title_ar: "",
        questions: [ this.blankQuestion() ]
      }
    },

    blankQuestion() {
      return {
        key: this.freshKey("q"),
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
      section.questions.push(this.blankQuestion())
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
