import { expect, test, Page } from "@playwright/test";
import { signIn, expectNoHorizontalOverflow } from "./helpers";

async function createTask(page: Page, title: string, answers = false) {
  await page.goto("/communications/new");
  await page.evaluate(async ({ title, answers }) => {
    const store = JSON.parse(document.querySelector<HTMLElement>("[data-units]")!.dataset.units!).find((unit: { name: string }) => unit.name === "QA Store Maarif");
    const token = document.querySelector<HTMLMetaElement>("meta[name=csrf-token]")!.content;
    const body = new URLSearchParams({
      "communication[title_fr]": title, "communication[body_fr]": "Read and complete this store task",
      "communication[format]": "task", "communication[requires_proof]": "1",
      "org_unit_ids[]": store.id, commit: "send",
    });
    if (answers) {
      body.set("communication[communication_questions_attributes][0][title_fr]", "Store observation");
      body.set("communication[communication_questions_attributes][0][question_type]", "short_text");
      body.set("communication[communication_questions_attributes][0][required]", "1");
      body.set("communication[communication_questions_attributes][0][position]", "0");
    }
    const response = await fetch("/communications", { method: "POST", headers: { "X-CSRF-Token": token }, body });
    if (!response.ok) throw new Error("Could not create store task fixture");
  }, { title, answers });
}

async function queued(page: Page) {
  return page.evaluate(async () => {
    const imports = JSON.parse(document.querySelector('script[type="importmap"]')!.textContent!).imports;
    const records = await (await import(imports.task_proof)).TaskProofQueue.all();
    return records.map((record: { id: string; entries: { name: string; value: string | Blob; filename?: string }[] }) => ({
      id: record.id,
      answers: record.entries.filter(entry => entry.name.startsWith("answers[")).map(entry => entry.value),
      files: record.entries.filter(entry => entry.value instanceof Blob).map(entry => entry.filename),
    }));
  });
}

async function openStoreTask(page: Page, title: string) {
  await page.goto("/inbox");
  await page.getByRole("link", { name: title, exact: true }).click();
  await expect(page).toHaveURL(/\/inbox\/\d+$/);
  for (const step of ["received", "read", "understood", "in_progress"]) {
    await expect(page.locator('input[name="step"]')).toHaveValue(step);
    await page.locator("form.task-card__action button[type=submit]").click();
    await expect(page.locator('input[name="step"]')).not.toHaveValue(step);
  }
  await expect(page.locator('input[name="proof_files[]"]')).toBeVisible();
  return new URL(page.url()).pathname;
}

test("area and HQ can open scoped progress while stores keep the execution handoff", async ({ page, context }) => {
  test.setTimeout(60_000);
  let monitorPath = "";
  await page.setViewportSize({ width: 390, height: 844 });
  await signIn(page, "hq");
  const title = `Persona handoff ${Date.now()}`;
  await createTask(page, title);
  for (const role of ["area", "hq", "store"] as const) {
    await context.clearCookies();
    await signIn(page, role);
    for (const locale of ["fr", "ar"]) {
      await page.goto(`/my_tasks?locale=${locale}`);
      await page.getByRole("link", { name: title, exact: true }).click();
      await expect(page).toHaveURL(/\/my_tasks\/\d+\?kind=task$/);
      const work = page.locator(".panel a.btn--primary");
      if (role === "store") {
        await expect(work).toHaveAttribute("href", /\/inbox\/\d+$/);
        await work.click();
        await expect(page.locator("article.task-card h1")).toHaveText(title);
      } else {
        await expect(work).toHaveAttribute("href", /\/communications\/\d+#store-\d+$/);
        monitorPath = (await work.getAttribute("href"))!;
        await work.click();
        await expect(page).toHaveURL(/\/communications\/\d+#store-\d+$/);
        await expect(page.locator(new URL(page.url()).hash)).toContainText("QA Store Maarif");
      }
      await expectNoHorizontalOverflow(page);
      if (locale === "ar") await expect(page.locator("html")).toHaveAttribute("dir", "rtl");
    }
  }
  for (const step of ["received", "read", "understood", "in_progress"]) {
    await expect(page.locator('input[name="step"]')).toHaveValue(step);
    await page.locator("form.task-card__action button[type=submit]").click();
    await expect(page.locator('input[name="step"]')).not.toHaveValue(step);
  }
  await page.locator('input[name="proof_files[]"]').setInputFiles({ name: "completed-proof.txt", mimeType: "text/plain", buffer: Buffer.from("Completed store work") });
  await page.locator('form[data-task-proof="true"] button[type=submit]').click();
  await expect(page.locator(".task-proof-gallery figcaption")).toHaveText("completed-proof.txt");
  const compose = page.locator(".delivery-comments__compose-wrap");
  await compose.locator("summary").click();
  await compose.locator("textarea").fill("Store completed the work and attached evidence");
  await compose.locator("button[type=submit]").click();
  await expect(page.locator(".delivery-comments__body").first()).toContainText("Store completed the work");
  await context.clearCookies();
  await signIn(page, "area");
  await page.goto(monitorPath);
  await expect(page.locator(".task-proof-gallery figcaption")).toHaveText("completed-proof.txt");
  await page.locator("details.delivery-timeline summary").click();
  await expect(page.locator(".delivery-timeline__list")).toContainText("QA Store");
  const reply = page.locator(".delivery-comments__reply-form").first();
  await reply.locator("summary").click();
  await reply.locator("textarea").fill("Area confirmed the evidence");
  await reply.locator("button[type=submit]").click();
  await expect(page.locator(".delivery-comments__reply")).toContainText("Area confirmed the evidence");
  await expectNoHorizontalOverflow(page);
});

test("discard confirmation preserves offline answers and files on cancel and deletes only the chosen queue record", async ({ page, context }) => {
  test.setTimeout(90_000);
  await page.setViewportSize({ width: 390, height: 844 });
  await signIn(page, "hq");
  const titles = [`Retain proof A ${Date.now()}`, `Retain proof B ${Date.now()}`];
  for (const title of titles) await createTask(page, title, true);
  await context.clearCookies();
  await signIn(page, "store");
  await page.evaluate(async () => {
    await navigator.serviceWorker.ready;
    if (!navigator.serviceWorker.controller) await new Promise(resolve => navigator.serviceWorker.addEventListener("controllerchange", resolve, { once: true }));
  });
  const paths = [];
  for (const title of titles) paths.push(await openStoreTask(page, title));
  // Cache both localized forms before going offline; subsequent reloads use the real worker.
  for (const locale of ["fr", "ar"]) for (const path of paths) await page.goto(`${path}?locale=${locale}`);
  await context.setOffline(true);
  for (let index = 0; index < paths.length; index++) {
    await page.goto(`${paths[index]}?locale=fr`);
    await page.locator('.task-card__answers input[type="text"]').fill(`Retained answer ${index}`);
    await page.locator('input[name="proof_files[]"]').setInputFiles({ name: `unsent-${index}.txt`, mimeType: "text/plain", buffer: Buffer.from(`Unsent evidence ${index}`) });
    await page.locator('form[data-task-proof="true"] button[type=submit]').click();
    await expect.poll(() => queued(page)).toHaveLength(index + 1);
  }
  const original = await queued(page);
  for (const locale of ["fr", "ar"]) {
    await page.goto(`${paths[1]}?locale=${locale}`);
    const panel = page.locator("[data-offline-workspace]");
    const row = panel.locator("p").filter({ has: page.locator(`a[href="${paths[1]}"]`) });
    const discard = row.getByRole("button").last();
    const expectedConfirmation = await panel.getAttribute("data-discard-confirm");
    await expect(page.locator("html")).toHaveAttribute("lang", locale);
    const dialog = page.waitForEvent("dialog");
    const click = discard.click();
    const confirmation = await dialog;
    expect(confirmation.message()).toBe(expectedConfirmation);
    expect(confirmation.message()).not.toContain("Translation missing");
    await confirmation.dismiss(); await click;
    await expect.poll(() => queued(page)).toEqual(original);
    await page.reload();
    await expect.poll(() => queued(page)).toEqual(original);
    await expectNoHorizontalOverflow(page);
  }
  const discard = page.locator("[data-offline-queue] p").filter({ has: page.locator(`a[href="${paths[1]}"]`) }).getByRole("button").last();
  const dialog = page.waitForEvent("dialog");
  const click = discard.click();
  await (await dialog).accept(); await click;
  await expect.poll(() => queued(page)).toEqual(original.filter(record => record.answers.includes("Retained answer 0")));
  expect((await queued(page))[0]).toMatchObject({ answers: ["Retained answer 0"], files: ["unsent-0.txt"] });
  await page.reload();
  await expect.poll(() => queued(page)).toEqual(original.filter(record => record.answers.includes("Retained answer 0")));
});
