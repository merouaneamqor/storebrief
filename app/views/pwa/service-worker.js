// Vazivo PWA service worker — shell cache + Web Push.

const CACHE_NAME = "vazivo-shell-v3"
const PRECACHE = ["/icon.png"]

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(PRECACHE)).then(() => self.skipWaiting())
  )
})

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key)))
    ).then(() => self.clients.claim())
  )
})

self.addEventListener("fetch", (event) => {
  const { request } = event
  if (request.method !== "GET") return

  // Never substitute the app icon for HTML navigations — that made every
  // offline/failed page look like a lone 512×512 icon.
  const isDocument = request.mode === "navigate" ||
    (request.headers.get("accept") || "").includes("text/html")

  event.respondWith(
    fetch(request)
      .then((response) => response)
      .catch(async () => {
        const cached = await caches.match(request)
        if (cached) return cached
        if (isDocument) {
          return new Response("Vazivo is offline. Try again when the network is back.", {
            status: 503,
            headers: { "Content-Type": "text/plain; charset=utf-8" }
          })
        }
        return caches.match("/icon.png")
      })
  )
})

function absoluteUrl(pathOrUrl) {
  try {
    return new URL(pathOrUrl || "/app", self.location.origin).href
  } catch (_error) {
    return new URL("/app", self.location.origin).href
  }
}

function askClientToNavigate(client, url) {
  try {
    client.postMessage({ type: "vazivo:navigate", url })
  } catch (_error) {
    // ignore
  }
}

async function openTargetUrl(targetUrl) {
  const url = absoluteUrl(targetUrl)
  const clientList = await self.clients.matchAll({ type: "window", includeUncontrolled: true })

  for (const client of clientList) {
    if (!client.url || !client.url.startsWith(self.location.origin)) continue
    if (!("focus" in client)) continue

    askClientToNavigate(client, url)

    if ("navigate" in client) {
      try {
        const navigated = await client.navigate(url)
        if (navigated) return navigated.focus()
      } catch (_error) {
        // Fall through to focus + postMessage.
      }
    }

    return client.focus()
  }

  if (self.clients.openWindow) {
    return self.clients.openWindow(url)
  }

  return undefined
}

self.addEventListener("push", (event) => {
  let data = {}
  try {
    data = event.data ? event.data.json() : {}
  } catch (_error) {
    data = { body: event.data ? event.data.text() : "" }
  }

  const title = data.title || "Vazivo"
  const targetUrl = data.url || "/app"
  const options = {
    body: data.body || "",
    icon: data.icon || "/icon.png",
    badge: data.badge || "/icon.png",
    data: { url: targetUrl },
    vibrate: [100, 50, 100]
  }

  event.waitUntil(self.registration.showNotification(title, options))
})

self.addEventListener("notificationclick", (event) => {
  event.notification.close()
  const targetUrl =
    (event.notification.data && event.notification.data.url) ||
    (event.notification.data && event.notification.data.path) ||
    "/app"

  event.waitUntil(openTargetUrl(targetUrl))
})
