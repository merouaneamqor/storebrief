// Files remain Blobs in IndexedDB, including after a tab closes. Never replay
// another user's or tenant's work after a login/account switch.
const TaskProofQueue = {
  async open() {
    return new Promise((resolve, reject) => {
      const request = indexedDB.open("vazivo-task-proofs", 1);
      request.onupgradeneeded = () => request.result.createObjectStore("submissions", { keyPath: "id" });
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  },
  async transaction(mode, callback) {
    const db = await this.open();
    try {
      return await new Promise((resolve, reject) => {
        const tx = db.transaction("submissions", mode);
        const request = callback(tx.objectStore("submissions"));
        tx.oncomplete = () => resolve(request.result);
        tx.onerror = () => reject(tx.error);
        tx.onabort = () => reject(tx.error);
      });
    } finally {
      db.close();
    }
  },
  all() { return this.transaction("readonly", store => store.getAll()); },
  put(record) { return this.transaction("readwrite", store => store.put(record)); },
  remove(id) { return this.transaction("readwrite", store => store.delete(id)); }
};

function owner() {
  return document.querySelector("meta[name=task-proof-owner]")?.content;
}

function showStatus(message, error = false) {
  document.querySelectorAll(".task-proof-sync, .task-proof-upload__status").forEach(element => {
    element.hidden = !message;
    element.textContent = message || "";
    element.classList.toggle("flash--alert", error);
  });
}

async function compressPhoto(file) {
  if (!["image/jpeg", "image/png", "image/webp"].includes(file.type)) return file;
  const url = URL.createObjectURL(file);
  try {
    const image = new Image();
    image.src = url;
    await image.decode();
    const ratio = Math.min(1, 1280 / Math.max(image.width, image.height));
    const canvas = document.createElement("canvas");
    canvas.width = Math.max(1, Math.round(image.width * ratio));
    canvas.height = Math.max(1, Math.round(image.height * ratio));
    canvas.getContext("2d").drawImage(image, 0, 0, canvas.width, canvas.height);
    const blob = await new Promise(resolve => canvas.toBlob(resolve, "image/jpeg", 0.75));
    if (!blob || blob.size >= file.size) return file;
    return new File([blob], file.name.replace(/\.[^.]+$/, "") + ".jpg", { type: "image/jpeg" });
  } finally {
    URL.revokeObjectURL(url);
  }
}

async function requestSubmission(record) {
  // The token may have rotated since the task was queued. The owner must still match.
  if (record.owner !== owner()) return null;
  const body = new FormData();
  record.entries.forEach(entry => {
    if (entry.value instanceof Blob) body.append(entry.name, entry.value, entry.filename);
    else body.append(entry.name, entry.value);
  });
  body.set("proof_request_id", record.id);
  body.delete("authenticity_token");
  const response = await fetch(record.url, {
    method: "POST",
    headers: { Accept: "application/json", "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content || "" },
    body
  });
  if (!response.headers.get("content-type")?.includes("application/json")) throw new Error("");
  const result = await response.json();
  if (!response.ok || result.status !== "ok") throw new Error(result.message || "");
  await TaskProofQueue.remove(record.id);
  return result;
}

let flushing = false;
async function flush() {
  if (flushing || !navigator.onLine || !owner()) return;
  flushing = true;
  try {
    const records = (await TaskProofQueue.all()).filter(record => record.owner === owner());
    let failure = false;
    let refreshCurrentTask = false;
    for (const record of records) {
      try {
        const result = await requestSubmission(record);
        refreshCurrentTask ||= !!result && new URL(result.location, location.origin).pathname === location.pathname;
      } catch (error) {
        failure = true;
        const fallback = document.querySelector(".task-proof-sync")?.dataset.error;
        showStatus(error.message || fallback, true);
      }
    }
    if (!failure) showStatus("");
    if (refreshCurrentTask) window.location.reload();
  } catch (_error) {
    // Browsers that disallow IndexedDB can still submit proof while online.
  } finally {
    flushing = false;
  }
}

document.addEventListener("change", event => {
  if (!event.target.matches('input[name="proof_files[]"]')) return;
  const list = event.target.closest("fieldset")?.querySelector(".task-proof-selected");
  if (!list) return;
  list.replaceChildren(...Array.from(event.target.files).map(file => {
    const item = document.createElement("li");
    item.textContent = file.name;
    return item;
  }));
});

document.addEventListener("submit", async event => {
  const form = event.target;
  if (!form.matches('form[data-task-proof="true"]')) return;
  event.preventDefault();
  event.stopImmediatePropagation();
  if (form.dataset.proofBusy === "true") return;
  const fields = form.querySelector(".task-proof-upload");
  if (!fields) return;
  const ownerAtSubmit = owner();
  if (!ownerAtSubmit) return;
  form.dataset.proofBusy = "true";
  const buttons = form.querySelectorAll('[type="submit"]');
  let saved = false;
  try {
    const data = new FormData(form);
    const files = data.getAll("proof_files[]").filter(file => file instanceof Blob && file.size);
    const types = fields.dataset.types.split(",");
    const uploads = [...data.values()].filter(value => value instanceof Blob && value.size);
    if (files.length > Number(fields.dataset.maxCount) || uploads.some(file => file.size > Number(fields.dataset.maxBytes) || !types.includes(file.type))) {
      throw new Error(fields.dataset.validationError);
    }
    const entries = [];
    for (const [name, value] of data.entries()) {
      if (value instanceof Blob) {
        if (!value.size) continue;
        const compressed = await compressPhoto(value);
        entries.push({ name, value: compressed, filename: compressed.name });
      } else {
        entries.push({ name, value });
      }
    }
    buttons.forEach(button => button.disabled = true);
    const existing = (await TaskProofQueue.all()).find(record => record.owner === ownerAtSubmit && record.url === form.action);
    const record = { id: existing?.id || crypto.randomUUID(), owner: ownerAtSubmit, url: form.action, entries };
    await TaskProofQueue.put(record);
    saved = true;
    if (navigator.onLine) {
      try {
        const result = await requestSubmission(record);
        if (result) window.location.assign(result.location);
      } catch (error) {
        showStatus(error.message || fields.dataset.error, true);
      }
    } else {
      showStatus(fields.dataset.queued);
    }
  } catch (error) {
    showStatus(error.message || fields.dataset.error, true);
    // Storage may be disabled or full: preserve the native online upload path.
    if (!saved && navigator.onLine && error.name !== "Error") HTMLFormElement.prototype.submit.call(form);
  } finally {
    form.dataset.proofBusy = "false";
    buttons.forEach(button => button.disabled = false);
  }
}, true);

window.addEventListener("online", flush);
document.addEventListener("turbo:load", flush);
document.addEventListener("DOMContentLoaded", flush);

export { TaskProofQueue, compressPhoto, requestSubmission };
