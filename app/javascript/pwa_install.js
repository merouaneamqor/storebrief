const DISMISS_KEY = "vazivo-pwa-install-dismissed"
const VISIT_KEY = "vazivo-pwa-install-visits"
const DISMISS_DAYS = 14

function isStandalone() {
  return (
    window.matchMedia("(display-mode: standalone)").matches ||
    window.navigator.standalone === true ||
    document.referrer.includes("android-app://")
  )
}

function isIos() {
  return /iphone|ipad|ipod/i.test(window.navigator.userAgent) ||
    (window.navigator.platform === "MacIntel" && window.navigator.maxTouchPoints > 1)
}

function isMobileViewport() {
  return window.matchMedia("(max-width: 860px), (hover: none) and (pointer: coarse)").matches
}

function wasDismissed() {
  try {
    const raw = localStorage.getItem(DISMISS_KEY)
    if (!raw) return false
    const until = Number(raw)
    if (!Number.isFinite(until)) return false
    if (Date.now() > until) {
      localStorage.removeItem(DISMISS_KEY)
      return false
    }
    return true
  } catch (_error) {
    return false
  }
}

function visitCount() {
  try {
    return Number(localStorage.getItem(VISIT_KEY) || "0") || 0
  } catch (_error) {
    return 0
  }
}

function bumpVisit() {
  try {
    const next = visitCount() + 1
    localStorage.setItem(VISIT_KEY, String(next))
    return next
  } catch (_error) {
    return 1
  }
}

window.pwaInstall = function pwaInstall() {
  return {
    open: false,
    canInstall: false,
    isIos: false,
    deferredPrompt: null,
    init() {
      if (isStandalone() || wasDismissed() || !isMobileViewport()) return
      if (window.location.pathname.startsWith("/inbox/")) return

      const visits = bumpVisit()
      if (visits < 2) return

      this.isIos = isIos()

      if (this.isIos) {
        this.open = true
        return
      }

      window.addEventListener("beforeinstallprompt", (event) => {
        event.preventDefault()
        this.deferredPrompt = event
        this.canInstall = true
        this.open = true
      })

      window.addEventListener("appinstalled", () => {
        this.open = false
        this.canInstall = false
        this.deferredPrompt = null
      })

      if (!this.isIos) {
        window.setTimeout(() => {
          if (!this.open && !isStandalone() && !wasDismissed() && visitCount() >= 2) {
            this.open = true
          }
        }, 1800)
      }
    },
    async install() {
      if (!this.deferredPrompt) {
        this.open = true
        return
      }
      this.deferredPrompt.prompt()
      try {
        await this.deferredPrompt.userChoice
      } catch (_error) {
        // ignore
      }
      this.deferredPrompt = null
      this.canInstall = false
      this.open = false
    },
    dismiss() {
      this.open = false
      try {
        localStorage.setItem(DISMISS_KEY, String(Date.now() + DISMISS_DAYS * 24 * 60 * 60 * 1000))
      } catch (_error) {
        // ignore
      }
    }
  }
}

if ("serviceWorker" in navigator) {
  const register = () => {
    navigator.serviceWorker
      .register("/service-worker")
      .then((registration) => registration.update())
      .catch(() => {})
  }

  if (document.readyState === "complete") {
    register()
  } else {
    window.addEventListener("load", register)
  }

  navigator.serviceWorker.addEventListener("message", (event) => {
    const data = event.data
    if (!data || data.type !== "vazivo:navigate" || !data.url) return

    try {
      const target = new URL(data.url, window.location.origin)
      if (target.origin !== window.location.origin) return

      if (window.Turbo && typeof window.Turbo.visit === "function") {
        window.Turbo.visit(target.pathname + target.search + target.hash)
      } else {
        window.location.assign(target.href)
      }
    } catch (_error) {
      // ignore
    }
  })
}
