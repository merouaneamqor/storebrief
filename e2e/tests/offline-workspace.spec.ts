import { expect, test, Page } from "@playwright/test";
import { signIn, expectNoHorizontalOverflow } from "./helpers";

const queue = async (page: Page) => page.evaluate(async () => {
  const imports = JSON.parse(document.querySelector('script[type="importmap"]')!.textContent!).imports;
  return (await (await import(imports.task_proof)).TaskProofQueue.all()).map((record: { id: string; conflict?: boolean }) => ({ id: record.id, conflict: !!record.conflict }));
});
const privatePaths = async (page: Page) => page.evaluate(async () => {
  const names = (await caches.keys()).filter(name => name.startsWith('vazivo-private-'));
  return (await Promise.all(names.map(async name => (await (await caches.open(name)).keys()).map(request => new URL(request.url).pathname)))).flat();
});

test("last-seen private workspaces survive offline navigation and protect queued conflicts across account switches", async ({ page, context, browser }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await signIn(page, "hq");
  await page.goto('/communications/new');
  const title = `Offline workspace task ${Date.now()}`;
  const taskCommunication = await page.evaluate(async title => {
    const store = JSON.parse(document.querySelector<HTMLElement>('[data-units]')!.dataset.units!).find((unit: { name: string }) => unit.name === 'QA Store Maarif');
    const token = document.querySelector<HTMLMetaElement>('meta[name=csrf-token]')?.content || '';
    const result = await fetch('/communications', { method: 'POST', headers: { 'X-CSRF-Token': token }, body: new URLSearchParams({ 'communication[title_fr]': title, 'communication[body_fr]': 'Original instructions', 'communication[format]': 'task', 'communication[requires_proof]': '1', 'org_unit_ids[]': store.id, commit: 'send' }) });
    if (!result.ok) throw new Error('Task fixture failed');
    return new URL(result.url).pathname;
  }, title);
  await page.goto('/kb_categories/new');
  const categoryId = await page.evaluate(async () => {
    const token = document.querySelector<HTMLMetaElement>('meta[name=csrf-token]')?.content || '';
    await fetch('/kb_categories', { method: 'POST', headers: { 'X-CSRF-Token': token }, body: new URLSearchParams({ 'kb_category[title_fr]': 'Offline browser handbook', 'kb_category[position]': '0' }) });
    const html = await (await fetch('/kb_articles/new')).text();
    const doc = new DOMParser().parseFromString(html, 'text/html');
    return doc.querySelector<HTMLOptionElement>('#kb_article_kb_category_id option[value]:not([value=""])')!.value;
  });
  const kbPath = await page.evaluate(async categoryId => {
    const token = document.querySelector<HTMLMetaElement>('meta[name=csrf-token]')?.content || '';
    const result = await fetch('/kb_articles', { method: 'POST', headers: { 'X-CSRF-Token': token }, body: new URLSearchParams({ 'kb_article[title_fr]': 'Private offline handbook', 'kb_article[body_fr]': 'Private handbook content for this tenant', 'kb_article[kb_category_id]': categoryId }) });
    const target = new URL(result.url).pathname;
    await fetch(`${target}/publish`, { method: 'POST', headers: { 'X-CSRF-Token': token } });
    return target;
  }, categoryId);
  await page.locator('form[action="/logout"] button').click();
  await expect(page).toHaveURL(/\/login$/);
  await signIn(page, 'store');
  await page.evaluate(async () => { await navigator.serviceWorker.ready; if (!navigator.serviceWorker.controller) await new Promise(resolve => navigator.serviceWorker.addEventListener('controllerchange', resolve, { once: true })); });
  await page.goto('/inbox');
  await page.getByRole('link', { name: title, exact: true }).click();
  await expect(page).toHaveURL(/\/inbox\/\d+$/);
  const taskUrl = page.url();
  await page.evaluate(async () => {
    const token = document.querySelector<HTMLMetaElement>('meta[name=csrf-token]')?.content || '';
    for (const step of ['received', 'read', 'understood', 'in_progress']) await fetch(`${location.pathname}/advance`, { method: 'POST', headers: { 'X-CSRF-Token': token, Accept: 'application/json' }, body: new URLSearchParams({ step }) });
  });
  for (const locale of ['fr', 'ar']) { await page.goto(`${taskUrl}?locale=${locale}`); await expectNoHorizontalOverflow(page); if (locale === 'ar') await expect(page.locator('html')).toHaveAttribute('dir', 'rtl'); }
  for (const path of ['/app', '/my_tasks', '/inbox', '/kb_articles', kbPath]) await page.goto(path);
  await expect.poll(() => privatePaths(page)).toEqual(expect.arrayContaining(['/inbox', '/my_tasks', '/kb_articles', kbPath]));
  await context.setOffline(true);
  await page.goto('/inbox'); await expect(page.getByRole('link', { name: title, exact: true })).toBeVisible();
  await page.goto('/my_tasks'); await expect(page.getByRole('link', { name: title, exact: true })).toBeVisible();
  await page.goto(kbPath); await expect(page.getByText('Private handbook content for this tenant')).toBeVisible();
  await expect(page.locator('[data-offline-workspace]')).toBeVisible();
  await page.goto(`${taskUrl}?locale=ar`); await expectNoHorizontalOverflow(page);
  await page.locator('input[name="proof_files[]"]').setInputFiles({ name: 'offline-proof.txt', mimeType: 'text/plain', buffer: Buffer.from('Queued private proof') });
  await page.locator('form[data-task-proof=true] button[type=submit]').click();
  await expect.poll(() => queue(page)).toHaveLength(1);
  await page.reload(); await expect.poll(() => queue(page)).toHaveLength(1);
  const oldSnapshot = await page.locator("input[name=task_snapshot]").inputValue();
  const hqContext = await browser.newContext(); const hq = await hqContext.newPage();
  await signIn(hq, 'hq'); await hq.goto(taskCommunication);
  await hq.evaluate(async target => {
    const token = document.querySelector<HTMLMetaElement>('meta[name=csrf-token]')?.content || '';
    const result = await fetch(`${target}/priority`, { method: 'POST', headers: { 'X-CSRF-Token': token }, body: new URLSearchParams({ _method: 'patch', 'communication[priority]': 'urgent' }) });
    if (!result.ok) throw new Error('HQ edit failed');
  }, taskCommunication);
  await context.setOffline(false);
  await expect.poll(async () => (await queue(page))[0]?.conflict).toBe(true);
  await page.locator('form[action="/logout"] button').click(); await expect(page).toHaveURL(/\/login$/);
  await signIn(page, 'area');
  await expect.poll(() => queue(page)).toHaveLength(1);
  await expect(page.locator('[data-offline-queue]')).toBeEmpty();
  await page.locator('form[action="/logout"] button').click(); await expect(page).toHaveURL(/\/login$/);
  await signIn(page, 'store');
  await page.goto(`${taskUrl}?locale=ar`);
  await expect(page.locator('input[name=task_snapshot]')).not.toHaveValue(oldSnapshot);
  await expectNoHorizontalOverflow(page);
  await page.locator('[data-offline-queue] button').filter({ hasText: /استعادة|Restaurer|Restore/ }).click();
  await page.locator('form[data-task-proof=true] button[type=submit]').click();
  await expect(page.locator('.task-proof-gallery figcaption')).toHaveText('offline-proof.txt');
  await expect.poll(() => queue(page)).toHaveLength(0);
  await hqContext.close();
  await page.locator('form[action="/logout"] button').click(); await expect(page).toHaveURL(/\/login$/);
  await expect.poll(() => privatePaths(page)).toHaveLength(0);
  await signIn(page, 'area');
  await context.setOffline(true);
  await page.goto(kbPath); await expect(page.getByText('Private handbook content for this tenant')).toHaveCount(0);
  await context.setOffline(false); await page.goto('/app');
  await page.locator('form[action="/logout"] button').click(); await expect(page).toHaveURL(/\/login$/);
  await page.locator('#tenant_slug').fill('qa-offline-other'); await page.locator('input[name=email]').fill('store@qa-offline-other.test'); await page.locator('input[name=password]').fill('password'); await page.locator('#password-login-form button[type=submit], #password-login-form input[type=submit]').first().click(); await expect(page).toHaveURL(/\/app$/);
  await context.setOffline(true); await page.goto(taskUrl); await expect(page.getByRole('heading', { name: title, exact: true })).toHaveCount(0);
});
