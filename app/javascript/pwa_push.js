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

function clearPushDismiss() {
  try {
    localStorage.removeItem(PUSH_DISMISS_KEY)
  } catch (_error) {
    // ignore
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

async function deleteServerSubscription(endpoint) {
  const res = await fetch("/push_subscription", {
    method: "DELETE",
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
      "X-CSRF-Token": csrfToken()
    },
    body: JSON.stringify(endpoint ? { endpoint } : {})
  })
  if (!res.ok && res.status !== 204) throw new Error("unsubscribe_failed")
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

async function clearPushSubscription() {
  if (!("serviceWorker" in navigator) || !("PushManager" in window)) {
    await deleteServerSubscription(null)
    clearPushDismiss()
    return
  }

  const registration = await navigator.serviceWorker.ready
  const subscription = await registration.pushManager.getSubscription()
  const endpoint = subscription?.endpoint || null
  if (subscription) await subscription.unsubscribe()
  await deleteServerSubscription(endpoint)
  clearPushDismiss()
}

window.pwaPush = function pwaPush() {
  return {
    open: false,
    manageOpen: false,
    busy: false,
    supported: false,
    subscribed: false,
    message: "",
    async init() {
      this.supported =
        pushConfigured() &&
        "Notification" in window &&
        "serviceWorker" in navigator &&
        "PushManager" in window

      if (!this.supported) return

      // Already allowed — keep the server subscription fresh.
      if (Notification.permission === "granted") {
        try {
          await ensurePushSubscription()
          this.subscribed = true
        } catch (_error) {
          this.subscribed = false
          if (isStandalone()) this.open = true
        }
        return
      }

      if (Notification.permission === "denied") return
      if (pushDismissed()) return

      // Ask only inside the installed PWA (required on iOS; intended UX on Android).
      if (isStandalone()) {
        this.open = true
      }
    },
    toggleManage() {
      this.message = ""
      if (this.subscribed) {
        this.open = false
        this.manageOpen = !this.manageOpen
        return
      }
      this.manageOpen = false
      this.open = !this.open
    },
    async enable() {
      if (this.busy) return
      this.busy = true
      this.message = ""
      try {
        const permission = await Notification.requestPermission()
        if (permission !== "granted") {
          this.open = false
          this.subscribed = false
          return
        }
        await ensurePushSubscription()
        this.subscribed = true
        this.open = false
        this.manageOpen = false
      } catch (_error) {
        this.subscribed = false
        this.open = false
      } finally {
        this.busy = false
      }
    },
    async reset() {
      if (this.busy) return
      this.busy = true
      this.message = ""
      try {
        await clearPushSubscription()
        if (Notification.permission === "granted") {
          await ensurePushSubscription()
          this.subscribed = true
          this.open = false
          this.manageOpen = true
          this.message = "reset"
        } else {
          this.subscribed = false
          this.manageOpen = false
          this.open = isStandalone()
        }
      } catch (_error) {
        this.subscribed = false
        this.manageOpen = false
        this.open = true
      } finally {
        this.busy = false
      }
    },
    async turnOff() {
      if (this.busy) return
      this.busy = true
      this.message = ""
      try {
        await clearPushSubscription()
        this.subscribed = false
        this.manageOpen = false
        this.open = isStandalone() && Notification.permission !== "denied"
      } catch (_error) {
        this.subscribed = false
        this.manageOpen = false
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
  clearPushDismiss()
})
