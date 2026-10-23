import { expect, test } from "@playwright/test";
import path from "node:path";
import { signIn, expectNoHorizontalOverflow } from "./helpers";

test("signature PNG and video persist offline and appear in reviewer and audit views", async ({ page, context }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await signIn(page, "hq");
  await page.goto("/communications/new");
  const title = `Signed video audit ${Date.now()}`;
  await page.evaluate(async title => {
    const store = JSON.parse(document.querySelector<HTMLElement>("[data-units]")!.dataset.units!).find((unit: { name: string }) => unit.name === "QA Store Maarif");
    const token = document.querySelector<HTMLMetaElement>("meta[name=csrf-token]")?.content || "";
    const body = new URLSearchParams({
      "communication[title_fr]": title, "communication[body_fr]": "Sign and attach video",
      "communication[format]": "task", "communication[requires_proof]": "1",
      "communication[communication_questions_attributes][0][title_fr]": "Signature",
      "communication[communication_questions_attributes][0][question_type]": "signature",
      "communication[communication_questions_attributes][0][position]": "0",
      "communication[communication_questions_attributes][0][required]": "1",
      "org_unit_ids[]": store.id, commit: "send",
    });
    const response = await fetch("/communications", { method: "POST", headers: { "X-CSRF-Token": token }, body });
    if (!response.ok) throw new Error("Could not create signature task");
  }, title);
  await context.clearCookies();
  await signIn(page, "store");
  await page.goto("/inbox");
  await page.getByRole("link", { name: title, exact: true }).click();
  await expect(page).toHaveURL(/\/inbox\/\d+$/);
  const taskUrl = page.url();
  await page.evaluate(async () => {
    const token = document.querySelector<HTMLMetaElement>("meta[name=csrf-token]")?.content || "";
    for (const step of ["received", "read", "understood", "in_progress"]) {
      const response = await fetch(`${location.pathname}/advance`, { method: "POST", headers: { "X-CSRF-Token": token, Accept: "application/json" }, body: new URLSearchParams({ step }) });
      if (!response.ok) throw new Error(`Could not advance ${step}`);
    }
  });
  for (const locale of ["fr", "ar"]) {
    await page.goto(`${taskUrl}?locale=${locale}`);
    await expect(page.locator("[data-signature-canvas]")).toBeVisible();
    await expectNoHorizontalOverflow(page);
    if (locale === "ar") await expect(page.locator("html")).toHaveAttribute("dir", "rtl");
  }
  const canvas = page.locator("[data-signature-canvas]");
  await canvas.evaluate(canvas => canvas.scrollIntoView({ block: "center" }));
  const box = (await canvas.boundingBox())!;
  await page.mouse.move(box.x + 20, box.y + 40);
  await page.mouse.down();
  await page.mouse.move(box.x + 70, box.y + 70);
  await page.mouse.move(box.x + 130, box.y + 30);
  await page.mouse.up();
  await expect.poll(() => page.locator("[data-signature-file]").evaluate((input: HTMLInputElement) => input.files?.[0]?.type)).toBe("image/png");
  await page.locator('input[name="proof_files[]"]').setInputFiles(path.resolve(__dirname, "../../test/fixtures/files/clip.webm"));
  await context.setOffline(true);
  await page.locator('form[data-task-proof="true"] button[type=submit]').click();
  await expect(page.locator(".task-proof-upload__status")).toBeVisible();
  const queuedMedia = async () => page.evaluate(async () => {
    const imports = JSON.parse(document.querySelector('script[type="importmap"]')!.textContent!).imports;
    const { TaskProofQueue, requestSubmission } = await import(imports.task_proof);
    const [record] = await TaskProofQueue.all();
    const signature = record.entries.find((entry: { name: string; value: Blob }) => entry.name.startsWith("answers[") && entry.value instanceof Blob);
    const video = record.entries.find((entry: { name: string; value: Blob }) => entry.name === "proof_files[]");
    return { signature: signature.value.type, video: video.value.type, blocked: await requestSubmission({ ...record, owner: "another-user" }) };
  });
  await expect.poll(queuedMedia).toEqual({ signature: "image/png", video: "video/webm", blocked: null });
  await page.route("**/inbox/*/advance", route => route.fulfill({ status: 422, contentType: "application/json", body: JSON.stringify({ status: "error", message: "Retry retained media" }) }));
  await context.setOffline(false);
  await expect(page.locator(".task-proof-upload__status")).toHaveText("Retry retained media");
  await page.reload();
  await expect.poll(queuedMedia).toEqual({ signature: "image/png", video: "video/webm", blocked: null });
  await page.unroute("**/inbox/*/advance");
  await page.evaluate(() => window.dispatchEvent(new Event("online")));
  await expect(page.locator(".task-proof-gallery video[controls]")).toHaveCount(1);
  await expect(page.locator(".task-card__answers img")).toHaveCount(1);
  await expect.poll(() => page.locator("video").evaluate((video: HTMLVideoElement) => video.videoWidth)).toBeGreaterThan(0);
  await page.reload();
  await expect(page.locator(".task-proof-gallery video")).toHaveCount(1);
  await context.clearCookies();
  await signIn(page, "hq");
  await page.goto("/communications");
  await page.getByRole("link", { name: title, exact: true }).click();
  await expect(page.locator(".brief-answers img")).toHaveCount(1);
  await expect(page.locator(".task-proof-gallery video")).toHaveCount(1);
  await page.goto("/audit_history");
  const evidence = page.locator("tr").filter({ hasText: title });
  await evidence.locator("summary").click();
  await expect(evidence.locator("video")).toBeVisible();
  await expect(evidence.locator("img")).toBeVisible();
});
