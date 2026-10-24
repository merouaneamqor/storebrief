// Keep signatures as PNG evidence. The task proof queue persists this File as a
// Blob alongside other form answers, including across offline reloads.
function setupSignatures() {
  document.querySelectorAll('[data-signature-pad]').forEach(pad => {
    if (pad.dataset.ready) return;
    pad.dataset.ready = 'true';
    const canvas = pad.querySelector('canvas');
    const input = pad.querySelector('[data-signature-file]');
    const ctx = canvas.getContext('2d');
    let drawing = false;
    let changed = 0;
    const point = event => {
      const rect = canvas.getBoundingClientRect();
      return [(event.clientX - rect.left) * canvas.width / rect.width, (event.clientY - rect.top) * canvas.height / rect.height];
    };
    canvas.addEventListener('click', event => event.preventDefault());
    canvas.addEventListener('pointerdown', event => {
      drawing = true;
      canvas.setPointerCapture(event.pointerId);
      ctx.beginPath();
      const [x, y] = point(event);
      ctx.moveTo(x, y);
      ctx.fillStyle = '#111';
      ctx.beginPath(); ctx.arc(x, y, 2, 0, 2 * Math.PI); ctx.fill();
      ctx.beginPath(); ctx.moveTo(x, y);
    });
    canvas.addEventListener('pointermove', event => {
      if (!drawing) return;
      ctx.lineWidth = 3; ctx.lineCap = 'round'; ctx.strokeStyle = '#111';
      ctx.lineTo(...point(event)); ctx.stroke();
    });
    const finish = () => {
      if (!drawing) return;
      drawing = false;
      const version = ++changed;
      // Synchronous data URL conversion avoids submitting before toBlob finishes.
      const bytes = Uint8Array.from(atob(canvas.toDataURL('image/png').split(',')[1]), char => char.charCodeAt(0));
      const transfer = new DataTransfer();
      transfer.items.add(new File([bytes], `signature-${version}.png`, { type: 'image/png' }));
      input.files = transfer.files;
      input.dispatchEvent(new Event('change', { bubbles: true }));
    };
    canvas.addEventListener('pointerup', finish);
    canvas.addEventListener('pointercancel', finish);
    pad.querySelector('[data-signature-clear]').addEventListener('click', () => {
      drawing = false; changed++;
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      input.value = '';
    });
  });
}
document.addEventListener('DOMContentLoaded', setupSignatures);
document.addEventListener('turbo:load', setupSignatures);
