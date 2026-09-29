const PUSH_DISMISS_KEY = "storebrief-push-dismissed"
const PUSH_DISMISS_DAYS = 7

function isStandalone() {
  return (
    window.matchMedia("(display-mode: standalone)").matches ||
    window.navigator.standalone === true ||
    document.referrer.includes("android-app://")
  )
}

function csrfToken() {
  return document.querySelector("meta[name='csrf-token']")?.content
}

function vapidPublicKey() {
  return document.querySelector("meta[name='vapid-public-key']")?.content || ""
}

function pushConfigured() {
  return document.querySelector("meta[name='push-configured']")?.content === "1"
}

function urlBase64ToUint8Array(base64String) {
  const padding = "=".repeat((4 - (base64String.length % 4)) % 4)
  const base64 = (base64String + padding).replace(/-/g, "+").replace(/_/g, "/")
  const raw = window.atob(base64)
  const output = new Uint8Array(raw.length)
  for (let i = 0; i < raw.length; i += 1) output[i] = raw.charCodeAt(i)
  return output
}

function pushDismissed() {
  try {
    const raw = localStorage.getItem(PUSH_DISMISS_KEY)
    if (!raw) return false
    const until = Number(raw)
    if (!Number.isFinite(until) || Date.now() > until) {
      localStorage.removeItem(PUSH_DISMISS_KEY)
      return false
    }
    return true
  } catch (_error) {
    return false
  }
}

async function saveSubscription(subscription) {
  const json = subscription.toJSON()
  const res = await fetch("/push_subscription", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
      "X-CSRF-Token": csrfToken()
    },
    body: JSON.stringify({
      endpoint: json.endpoint,
      keys: {
        p256dh: json.keys.p256dh,
        auth: json.keys.auth
      }
    })
  })
  if (!res.ok) throw new Error("subscribe_failed")
}

async function ensurePushSubscription() {
  if (!pushConfigured() || !("serviceWorker" in navigator) || !("PushManager" in window)) {
    return false
  }
  if (Notification.permission !== "granted") return false

  const key = vapidPublicKey()
  if (!key) return false

  const registration = await navigator.serviceWorker.ready
  let subscription = await registration.pushManager.getSubscription()
  if (!subscription) {
    subscription = await registration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: urlBase64ToUint8Array(key)
    })
  }
  await saveSubscription(subscription)
  return true
}

window.pwaPush = function pwaPush() {
  return {
    open: false,
    busy: false,
    supported: false,
    init() {
      this.supported =
        pushConfigured() &&
        "Notification" in window &&
        "serviceWorker" in navigator &&
        "PushManager" in window

      if (!this.supported) return

      // Already allowed — keep the server subscription fresh.
      if (Notification.permission === "granted") {
        ensurePushSubscription().catch(() => {})
        return
      }

      if (Notification.permission === "denied") return
      if (pushDismissed()) return

      // Ask only inside the installed PWA (required on iOS; intended UX on Android).
      if (isStandalone()) {
        this.open = true
      }
    },
    async enable() {
      if (this.busy) return
      this.busy = true
      try {
        const permission = await Notification.requestPermission()
        if (permission !== "granted") {
          this.open = false
          return
        }
        await ensurePushSubscription()
        this.open = false
      } catch (_error) {
        this.open = false
      } finally {
        this.busy = false
      }
    },
    dismiss() {
      this.open = false
      try {
        localStorage.setItem(
          PUSH_DISMISS_KEY,
          String(Date.now() + PUSH_DISMISS_DAYS * 24 * 60 * 60 * 1000)
        )
      } catch (_error) {
        // ignore
      }
    }
  }
}

// After install, ask for notifications on the next standalone launch.
window.addEventListener("appinstalled", () => {
  try {
    localStorage.removeItem(PUSH_DISMISS_KEY)
  } catch (_error) {
    // ignore
  }
})
