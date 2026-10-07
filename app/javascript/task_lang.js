window.taskLang = function taskLang(initial, langs) {
  const list = Array.isArray(langs) ? langs : []
  return {
    lang: initial || list[0] || "fr",
    langs: list,
    nextLang() {
      if (!this.langs.length) return
      const i = this.langs.indexOf(this.lang)
      this.lang = this.langs[(i + 1) % this.langs.length]
    },
    prevLang() {
      if (!this.langs.length) return
      const i = this.langs.indexOf(this.lang)
      this.lang = this.langs[(i - 1 + this.langs.length) % this.langs.length]
    }
  }
}
