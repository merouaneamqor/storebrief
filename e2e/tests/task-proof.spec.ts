import { expect, test } from "@playwright/test";
import { signIn } from "./helpers";

// HTTP rejection is mocked here; offline-workspace.spec covers the real worker.
test.use({ serviceWorkers: "block" });

test("offline multi-file proof survives storage, compresses photos and syncs once", async ({ page, context }) => {
  await signIn(page, "hq");
  await page.goto("/communications/new");
  const title = `Offline proof ${Date.now()}`;
  await page.evaluate(async title => {
    const units = JSON.parse(document.querySelector<HTMLElement>("[data-units]")!.dataset.units!);
    const store = units.find((unit: { name: string }) => unit.name === "QA Store Maarif");
    const token = document.querySelector<HTMLMetaElement>("meta[name=csrf-token]")!.content;
    const body = new URLSearchParams({
      "communication[title_fr]": title,
      "communication[body_fr]": "Attach proof offline",
      "communication[format]": "task",
      "communication[requires_proof]": "1",
      "org_unit_ids[]": store.id,
      commit: "send",
    });
    const response = await fetch("/communications", { method: "POST", headers: { "X-CSRF-Token": token }, body });
    if (!response.ok) throw new Error("Could not create proof task");
  }, title);

  await context.clearCookies();
  await signIn(page, "store");
  await page.goto("/inbox");
  await page.getByRole("link", { name: title, exact: true }).click();
  await expect(page).toHaveURL(/\/inbox\/\d+$/);
  const taskUrl = page.url();
  await page.evaluate(async () => {
    const token = document.querySelector<HTMLMetaElement>("meta[name=csrf-token]")!.content;
    for (const step of ["received", "read", "understood", "in_progress"]) {
      const response = await fetch(`${location.pathname}/advance`, {
        method: "POST", headers: { "X-CSRF-Token": token, Accept: "application/json" }, body: new URLSearchParams({ step }),
      });
      if (!response.ok) throw new Error(`Could not advance ${step}`);
    }
  });
  await page.reload();
  const photoBase64 = await page.evaluate(() => {
    const canvas = document.createElement("canvas");
    canvas.width = 1800;
    canvas.height = 1200;
    const ctx = canvas.getContext("2d")!;
    const pixels = ctx.createImageData(canvas.width, canvas.height);
    for (let index = 0; index < pixels.data.length; index += 4) {
      pixels.data[index] = index % 251;
      pixels.data[index + 1] = (index * 7) % 253;
      pixels.data[index + 2] = (index * 13) % 255;
      pixels.data[index + 3] = 255;
    }
    ctx.putImageData(pixels, 0, 0);
    return canvas.toDataURL("image/png").split(",")[1];
  });
  await context.setOffline(true);
  await page.locator('input[name="proof_files[]"]').setInputFiles([
    { name: "shelf.png", mimeType: "image/png", buffer: Buffer.from(photoBase64, "base64") },
    { name: "notes.txt", mimeType: "text/plain", buffer: Buffer.from("Proof notes") },
  ]);
  await page.locator('form[data-task-proof="true"] button[type=submit]').click();
  await expect(page.locator(".task-proof-upload__status")).not.toBeEmpty();

  const queued = await page.evaluate(async () => {
    const imports = JSON.parse(document.querySelector('script[type="importmap"]')!.textContent!).imports;
    const { TaskProofQueue, requestSubmission } = await import(imports.task_proof);
    const [record] = await TaskProofQueue.all();
    const image = record.entries.find((entry: { filename?: string }) => entry.filename === "shelf.jpg");
    const bitmap = await createImageBitmap(image.value);
    const blocked = await requestSubmission({ ...record, owner: "another-tenant:another-user" });
    return { count: (await TaskProofQueue.all()).length, width: bitmap.width, size: image.value.size, blocked };
  });
  expect(queued.count).toBe(1);
  expect(queued.width).toBeLessThanOrEqual(1280);
  expect(queued.size).toBeLessThan(Buffer.from(photoBase64, "base64").length);
  expect(queued.blocked).toBeNull();

  // An explicit rejection must preserve both files for correction or retry.
  await page.route("**/inbox/*/advance", route => route.fulfill({
    status: 422, contentType: "application/json", body: JSON.stringify({ status: "error", message: "Please retry proof" }),
  }));
  await context.setOffline(false);
  await expect(page.locator(".task-proof-upload__status")).toHaveText("Please retry proof");
  await page.unroute("**/inbox/*/advance");
  await page.evaluate(() => window.dispatchEvent(new Event("online")));
  await expect(page.locator(".task-proof-gallery figcaption a")).toHaveCount(2);
  await expect.poll(async () => page.evaluate(async () => {
    const imports = JSON.parse(document.querySelector('script[type="importmap"]')!.textContent!).imports;
    const { TaskProofQueue } = await import(imports.task_proof);
    return (await TaskProofQueue.all()).length;
  })).toBe(0);

  await page.goto(taskUrl);
  await expect(page.locator(".task-proof-gallery figcaption a")).toHaveCount(2);
  await expect(page.locator(".task-proof-gallery figcaption")).toContainText(["shelf.jpg", "notes.txt"]);
  await expect(page.locator('form[data-task-proof="true"]')).toHaveCount(0);
});
