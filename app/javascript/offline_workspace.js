import { TaskProofQueue } from "task_proof";

const currentOwner = () => document.querySelector('meta[name="task-proof-owner"]')?.content;
async function refreshWorkspace() {
  const panel = document.querySelector('[data-offline-workspace]');
  if (!panel) return;
  let records = [];
  try { records = (await TaskProofQueue.all()).filter(record => record.owner === currentOwner()); } catch (_) {}
  panel.hidden = navigator.onLine && !records.length;
  panel.querySelector('[data-offline-banner]').textContent = navigator.onLine ? (records.length ? panel.dataset.pending : '') : panel.dataset.offline;
  const list = panel.querySelector('[data-offline-queue]');
  list.replaceChildren();
  if (records.some(record => record.error || record.conflict)) {
    const help = document.createElement('p'); help.textContent = panel.dataset.recovery; list.append(help);
  }
  for (const record of records) {
    const row = document.createElement('p');
    row.textContent = record.error || panel.dataset.pending;
    const link = document.createElement('a');
    link.textContent = panel.dataset.open;
    // Queue records are created from same-origin task forms. Validate again before navigation.
    const target = new URL(record.url, location.origin);
    if (target.origin !== location.origin || !/^\/inbox\/\d+\/(advance|complete)$/.test(target.pathname)) continue;
    link.href = target.pathname.replace(/\/(advance|complete)$/, '');
    row.append(' ', link);
    const form = [...document.querySelectorAll('form[data-task-proof="true"]')].find(form => form.action === record.url);
    if (form) {
      const restore = document.createElement('button');
      restore.type = 'button'; restore.className = 'btn btn--sm'; restore.textContent = panel.dataset.restore;
      restore.onclick = () => {
        for (const entry of record.entries) {
          if (['task_snapshot', 'authenticity_token', 'proof_owner'].includes(entry.name)) continue;
          const inputs = [...form.elements].filter(input => input.name === entry.name);
          if (entry.value instanceof Blob) {
            const input = inputs.find(input => input.type === 'file');
            if (!input) continue;
            const transfer = new DataTransfer();
            const entries = record.entries.filter(value => value.name === entry.name && value.value instanceof Blob);
            entries.forEach(value => transfer.items.add(new File([value.value], value.filename, { type: value.value.type })));
            input.files = transfer.files;
            input.dispatchEvent(new Event('change', { bubbles: true }));
          } else {
            inputs.forEach(input => {
              if (['checkbox', 'radio'].includes(input.type)) input.checked = record.entries.some(value => value.name === input.name && value.value === input.value);
              else input.value = entry.value;
            });
          }
        }
        form.scrollIntoView({ block: 'center' });
      };
      row.append(' ', restore);
    }
    const discard = document.createElement('button');
    discard.type = 'button'; discard.className = 'btn btn--sm'; discard.textContent = panel.dataset.discard;
    discard.onclick = () => {
      if (panel.dataset.discardConfirm && window.confirm(panel.dataset.discardConfirm)) TaskProofQueue.remove(record.id);
    };
    row.append(' ', discard); list.append(row);
  }
}
['DOMContentLoaded', 'turbo:load', 'vazivo:proof-queue'].forEach(event => document.addEventListener(event, refreshWorkspace));
window.addEventListener('online', refreshWorkspace);
window.addEventListener('offline', refreshWorkspace);

// Browser/Turbo history must re-enter through the current owner-scoped worker.
window.addEventListener('pagehide', event => {
  if (event.persisted && currentOwner()) document.body.replaceChildren();
});
window.addEventListener('pageshow', event => {
  if (event.persisted) window.location.reload();
});
