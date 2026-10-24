import { expect, test } from "@playwright/test";
import path from "node:path";
import { signIn, expectNoHorizontalOverflow } from "./helpers";

for (const locale of ["fr", "ar"] as const) {
  test(`attached draft retains its audience and remains editable in ${locale}`, async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    const errors: string[] = [];
    page.on("pageerror", error => errors.push(error.message));
    await signIn(page, "hq");
    await page.goto(`/communications/new?locale=${locale}`);
    await page.waitForFunction(() => Boolean((document.querySelector(".brief-form") as HTMLElement & { _x_dataStack?: unknown })?._x_dataStack));
    const title = `Authoring recovery ${locale} ${Date.now()}`;
    await page.locator("#communication_title_fr").fill(title);
    await page.locator("#communication_body_fr").fill("Read the PDF and keep this audience.");
    await page.locator(".brief-topbar__actions button").nth(1).click();
    await page.locator('input[name="communication_format_ui"][value="task"]').check();
    await page.locator('input[type="file"]').setInputFiles(path.resolve(__dirname, "../../test/fixtures/files/notice.pdf"));
    const targets = page.locator(".brief-targets-block");
    await targets.locator("label.brief-target").filter({ hasText: "QA Region" }).locator('input[type="checkbox"]').check();
    await targets.locator('select[x-model="role"]').selectOption("store");
    await targets.locator('select[x-model="storeFormat"]').selectOption("supermarket");
    await targets.locator('select[x-model="cluster"]').selectOption("casa-nord");
    await expect(page.locator(".brief-assignment-preview__list li")).toHaveCount(1);
    await expect(page.locator(".brief-assignment-preview__list li")).toContainText("QA Store Maarif");
    await page.locator('.brief-settings__actions button[value="draft"]').click();
    await expect(page).toHaveURL(/\/communications\/\d+\/edit$/);
    await expect(page.locator(".brief-form")).toHaveAttribute("data-title-fr", title);
    await page.waitForFunction(() => Boolean((document.querySelector(".brief-form") as HTMLElement & { _x_dataStack?: unknown })?._x_dataStack));
    await expect(page.locator("html")).toHaveAttribute("dir", locale === "ar" ? "rtl" : "ltr");
    expect(await page.locator("form.brief-editor-form").evaluate(form => (form as HTMLFormElement).checkValidity())).toBe(true);
    await expect(page.locator(".brief-attachments")).toContainText("notice.pdf");
    await page.locator("#communication_body_fr").fill("Corrected instructions with the same attachment.");
    await page.locator(".brief-topbar__actions button").nth(1).click();
    await expect(targets.locator("label.brief-target").filter({ hasText: "QA Region" }).locator('input[type="checkbox"]')).toBeChecked();
    await expect(targets.locator('select[x-model="role"]')).toHaveValue("store");
    await expect(targets.locator('select[x-model="storeFormat"]')).toHaveValue("supermarket");
    await expect(targets.locator('select[x-model="cluster"]')).toHaveValue("casa-nord");
    await expect(page.locator(".brief-assignment-preview__list li")).toHaveCount(1);
    await page.locator('.brief-settings__actions button[value="draft"]').click();
    await expect(page.locator(".brief-form")).toHaveAttribute("data-body-fr", "Corrected instructions with the same attachment.");
    await page.reload();
    await expect(page.locator(".brief-form")).toHaveAttribute("data-body-fr", "Corrected instructions with the same attachment.");
    await expect(page.locator(".brief-attachments")).toContainText("notice.pdf");
    await expectNoHorizontalOverflow(page);
    expect(errors).toEqual([]);
  });
}
