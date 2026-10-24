import { expect, test } from "@playwright/test";
import { ACCOUNTS, TENANT, expectNoHorizontalOverflow, setLocale, signIn } from "./helpers";

for (const locale of ["fr", "ar"] as const) {
  test(`a store user resumes a task after session expiry and a password retry (${locale})`, async ({ page, context }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await signIn(page, "store");
    await setLocale(page, locale);
    await page.goto("/inbox");
    await page.getByRole("link", { name: "Tache QA vitrine", exact: true }).click();
    await expect(page).toHaveURL(/\/inbox\/\d+$/);
    const taskUrl = `${page.url()}?locale=${locale}`;

    await context.clearCookies();
    await page.goto(taskUrl);
    await expect(page).toHaveURL(/\/login$/);
    await page.goto(`/login?locale=${locale}`);
    const form = page.locator("#password-login-form");
    await form.locator("#tenant_slug").fill(TENANT);
    await form.locator("input[name=email]").fill(ACCOUNTS.store);
    await form.locator("input[name=password]").fill("wrong-password");
    await form.locator("button[type=submit]").click();
    await expect(page.locator(".m-flash--alert")).toBeVisible();
    await expectNoHorizontalOverflow(page);

    await form.locator("input[name=password]").fill("password");
    await form.locator("button[type=submit]").click();
    await expect(page).toHaveURL(taskUrl);
    await expect(page.locator("h1")).toContainText("Tache QA vitrine");
    await expect(page.locator("html")).toHaveAttribute("dir", locale === "ar" ? "rtl" : "ltr");
    await expectNoHorizontalOverflow(page);

    await page.evaluate(async () => {
      const token = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')!.content;
      await fetch("/logout", { method: "DELETE", headers: { "X-CSRF-Token": token } });
    });
    await signIn(page, "store");
    await setLocale(page, "fr");
  });
}
