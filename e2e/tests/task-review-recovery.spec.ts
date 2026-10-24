import { expect, test, Page } from "@playwright/test";
import path from "node:path";
import { signIn, expectNoHorizontalOverflow } from "./helpers";

async function createApprovalTask(page: Page, title: string) {
  await page.goto("/communications/new");
  return page.evaluate(async title => {
    const store = JSON.parse(document.querySelector<HTMLElement>("[data-units]")!.dataset.units!).find((unit: { name: string }) => unit.name === "QA Store Maarif");
    const token = document.querySelector<HTMLMetaElement>("meta[name=csrf-token]")!.content;
    const body = new URLSearchParams({
      "communication[title_fr]": title, "communication[body_fr]": "Submit evidence for review and correct the rejected answer",
      "communication[format]": "task", "communication[requires_approval]": "1", "communication[requires_proof]": "1",
      "communication[communication_questions_attributes][0][title_fr]": "Observation",
      "communication[communication_questions_attributes][0][question_type]": "short_text",
      "communication[communication_questions_attributes][0][required]": "1",
      "communication[communication_questions_attributes][0][position]": "0",
      "communication[communication_questions_attributes][1][title_fr]": "Optional checks",
      "communication[communication_questions_attributes][1][question_type]": "multi_choice",
      "communication[communication_questions_attributes][1][position]": "1",
      "communication[communication_questions_attributes][1][options]": JSON.stringify([{ label_fr: "Option A", label_ar: "الخيار أ" }]),
      "communication[communication_questions_attributes][2][title_fr]": "Signature",
      "communication[communication_questions_attributes][2][question_type]": "signature",
      "communication[communication_questions_attributes][2][position]": "2",
      "org_unit_ids[]": store.id, commit: "send",
    });
    const response = await fetch("/communications", { method: "POST", headers: { "X-CSRF-Token": token }, body });
    if (!response.ok) throw new Error("Could not create task review fixture");
    return new URL(response.url).pathname;
  }, title);
}

for (const locale of ["fr", "ar"] as const) {
  test(`${locale}: store can inspect submitted answers, correct rejection and retain proof through final review`, async ({ page, context }) => {
    test.setTimeout(90_000);
    await page.setViewportSize({ width: 390, height: 844 });
    await signIn(page, "hq");
    const title = `Review recovery ${locale} ${Date.now()}`;
    const monitorPath = await createApprovalTask(page, title);
    await context.clearCookies();
    await signIn(page, "store");
    await page.goto(`/inbox?locale=${locale}`);
    await page.getByRole("link", { name: title, exact: true }).click();
    await expect(page).toHaveURL(/\/inbox\/\d+$/);
    const taskPath = new URL(page.url()).pathname;
    for (const step of ["received", "read", "understood", "in_progress"]) {
      await expect(page.locator('input[name="step"]')).toHaveValue(step);
      await page.locator("form.task-card__action button[type=submit]").click();
      await expect(page.locator('input[name="step"]')).not.toHaveValue(step);
    }
    const choices = page.locator('.task-card__answers input[type="checkbox"]');
    await expect(choices).not.toBeChecked();
    await page.locator('.task-card__answers input[type="text"]').fill("Original observation");
    await choices.check();
    await page.locator("[data-signature-file]").setInputFiles(path.resolve(__dirname, "../../test/fixtures/files/signature.png"));
    await page.locator('input[name="proof_files[]"]').setInputFiles({ name: "review-proof.txt", mimeType: "text/plain", buffer: Buffer.from("Evidence to retain during correction") });
    await page.locator('form[data-task-proof="true"] button[type=submit]').click();
    await expect(page.locator(".task-card__answers")).toContainText("Original observation");
    await expect(page.locator('.task-card__answers img[alt="Signature"]')).toHaveCount(1);
    await expect(page.locator(".task-card__answers")).toContainText(locale === "ar" ? "الخيار أ" : "Option A");
    await expect(page.locator("form.task-card__action")).toHaveCount(0);
    await expect(page.locator(".task-proof-gallery figcaption")).toHaveText("review-proof.txt");
    await expectNoHorizontalOverflow(page);

    const firstReviewer = locale === "fr" ? "area" : "hq";
    const finalReviewer = locale === "fr" ? "hq" : "area";
    const rejection = `Correction requested ${locale}`;
    await context.clearCookies(); await signIn(page, firstReviewer);
    await page.goto(`${monitorPath}?locale=${locale}`);
    let review = page.locator('form[action$="/verdict"]').first();
    await review.locator("textarea").fill(rejection);
    await review.locator('button[value="non_conforme"]').click();
    await expect(page.locator(".verdict-chip")).toContainText(rejection);
    await expectNoHorizontalOverflow(page);

    await context.clearCookies(); await signIn(page, "store");
    const correctionLocale = locale === "fr" ? "ar" : "fr";
    await page.goto(`${taskPath}?locale=${correctionLocale}`);
    await expect(page.locator('input[type="text"][name^="answers["]')).toHaveValue("Original observation");
    await expect(choices).toBeChecked();
    await expect(page.locator(".task-card")).toContainText(rejection);
    await expect(page.locator(".task-proof-gallery figcaption")).toHaveText("review-proof.txt");
    await page.locator('.task-card__answers input[type="text"]').fill("Corrected observation");
    await choices.uncheck();
    await page.locator('form[data-task-proof="true"] button[type=submit]').click();
    await expect(page.locator(".task-card__answers")).toContainText("Corrected observation");
    await expect(page.locator(".task-card__answers")).not.toContainText("Option A");
    await expect(page.locator(".task-card__answers")).not.toContainText("الخيار أ");
    await expect(page.locator('.task-card__answers img[alt="Signature"]')).toHaveCount(1);
    await expect(page.locator(".task-proof-gallery figcaption")).toHaveText("review-proof.txt");
    await expect(page.locator("form.task-card__action")).toHaveCount(0);

    await context.clearCookies(); await signIn(page, finalReviewer);
    await page.goto(`${monitorPath}?locale=${locale}`);
    await expect(page.locator(".brief-answers")).toContainText("Corrected observation");
    await expect(page.locator(".brief-answers__row").filter({ hasText: "Optional checks" }).locator("strong")).toHaveText("-");
    review = page.locator('form[action$="/verdict"]').first();
    await review.locator("textarea").fill(`Correction accepted ${locale}`);
    await review.locator('button[value="conforme"]').click();
    await expect(page.locator(".verdict-chip")).toContainText(`Correction accepted ${locale}`);
    await page.locator(".delivery-timeline summary").click();
    await expect(page.locator(".delivery-timeline__list")).toContainText(rejection);
    await expect(page.locator(".task-proof-gallery figcaption")).toHaveText("review-proof.txt");
    await expectNoHorizontalOverflow(page);
    await context.clearCookies(); await signIn(page, "store");
    await page.goto(`${taskPath}?locale=${locale}`);
    await expect(page.locator(".task-card__answers")).toContainText("Corrected observation");
    await expect(page.locator("form.task-card__action")).toHaveCount(0);
    await expect(page.locator("html")).toHaveAttribute("lang", locale);
    if (locale === "ar") await expect(page.locator("html")).toHaveAttribute("dir", "rtl");
    await expectNoHorizontalOverflow(page);
  });
}
