window.offlineSync = function offlineSync() {
  return {
    online: navigator.onLine,
    init() {
      window.addEventListener("online", () => {
        this.online = true;
        this.flushQueue();
      });
      window.addEventListener("offline", () => {
        this.online = false;
      });
      if (this.online) this.flushQueue();
    },
    async flushQueue() {
      let queue = [];
      try {
        queue = await OfflineQueue.all();
      } catch (_error) {
        return;
      }
      if (!queue.length) return;

      const token = document.querySelector("meta[name='csrf-token']")?.content;
      const res = await fetch("/sync/checklist_responses", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": token,
          Accept: "application/json"
        },
        body: JSON.stringify({ responses: queue })
      });

      if (res.ok) {
        await OfflineQueue.clear();
      }
    }
  };
};

window.checklistFill = function checklistFill(config) {
  return {
    ...config,
    previews: {},
    compressed: {},
    hydrate() {
      // no-op placeholder for future cached shells
    },
    async compressPhoto(event) {
      const file = event.target.files?.[0];
      if (!file) return;
      const form = event.target.closest("form");
      const itemId = form?.closest("[data-item-id]")?.dataset?.itemId;
      const dataUrl = await ImageCompress.toJpegDataUrl(file, 1280, 0.7);
      if (itemId) {
        this.previews[itemId] = dataUrl;
        this.compressed[itemId] = dataUrl;
      }
    },
    async submitItem(event, itemId, requiresPhoto) {
      const form = event.target;
      const notes = form.notes?.value || "";
      const clientUuid = crypto.randomUUID();
      const photoData = this.compressed[itemId] || null;

      if (requiresPhoto && !photoData && !form.photo?.files?.length) {
        alert("Photo required");
        return;
      }

      const payload = {
        delivery_id: this.deliveryId,
        item_id: itemId,
        completed: true,
        notes,
        client_uuid: clientUuid,
        photo_data: photoData
      };

      if (!navigator.onLine) {
        await OfflineQueue.push(payload);
        form.closest(".checklist-item")?.classList.add("is-done");
        form.remove();
        return;
      }

      if (photoData) {
        const res = await fetch(this.syncUrl, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "X-CSRF-Token": this.csrf,
            Accept: "application/json"
          },
          body: JSON.stringify({ responses: [payload] })
        });
        if (res.ok) {
          window.location.reload();
          return;
        }
      }

      const body = new FormData();
      body.append("authenticity_token", this.csrf);
      body.append("item_id", itemId);
      body.append("notes", notes);
      body.append("client_uuid", clientUuid);
      if (form.photo?.files?.[0]) body.append("photo", form.photo.files[0]);

      const response = await fetch(`${this.submitUrlBase}/submit_item`, {
        method: "POST",
        headers: { Accept: "text/html" },
        body
      });
      if (response.redirected) {
        window.location = response.url;
      } else {
        window.location.reload();
      }
    }
  };
};

document.addEventListener("click", (event) => {
  if (!event.target.closest(".app-sidebar a")) return;

  const toggle = document.getElementById("app-nav-toggle");
  if (toggle) toggle.checked = false;
}, true);

const OfflineQueue = {
  dbName: "storebrief-offline",
  storeName: "checklist_responses",
  async open() {
    return new Promise((resolve, reject) => {
      const req = indexedDB.open(this.dbName, 1);
      req.onupgradeneeded = () => {
        const db = req.result;
        if (!db.objectStoreNames.contains(this.storeName)) {
          db.createObjectStore(this.storeName, { keyPath: "client_uuid" });
        }
      };
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error);
    });
  },
  async push(item) {
    const db = await this.open();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(this.storeName, "readwrite");
      tx.objectStore(this.storeName).put(item);
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
    });
  },
  async all() {
    const db = await this.open();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(this.storeName, "readonly");
      const req = tx.objectStore(this.storeName).getAll();
      req.onsuccess = () => resolve(req.result || []);
      req.onerror = () => reject(req.error);
    });
  },
  async clear() {
    const db = await this.open();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(this.storeName, "readwrite");
      tx.objectStore(this.storeName).clear();
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
    });
  }
};

const ImageCompress = {
  toJpegDataUrl(file, maxWidth = 1280, quality = 0.7) {
    return new Promise((resolve, reject) => {
      const img = new Image();
      const url = URL.createObjectURL(file);
      img.onload = () => {
        const scale = Math.min(1, maxWidth / img.width);
        const canvas = document.createElement("canvas");
        canvas.width = Math.round(img.width * scale);
        canvas.height = Math.round(img.height * scale);
        const ctx = canvas.getContext("2d");
        ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
        URL.revokeObjectURL(url);
        resolve(canvas.toDataURL("image/jpeg", quality));
      };
      img.onerror = reject;
      img.src = url;
    });
  }
};
