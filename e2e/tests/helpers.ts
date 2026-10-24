import { expect, Page } from "@playwright/test";

export const TENANT = "qa-vazivo";
export const ACCOUNTS = {
  hq: "hq@qa-vazivo.test",
  area: "area@qa-vazivo.test",
  store: "store@qa-vazivo.test",
} as const;

export async function signIn(page: Page, role: keyof typeof ACCOUNTS) {
  await page.goto("/login");
  const form = page.locator("#password-login-form");
  await form.locator("#tenant_slug").fill(TENANT);
  await form.locator("input[name=email]").fill(ACCOUNTS[role]);
  await form.locator("input[name=password]").fill("password");
  await form.locator("button[type=submit], input[type=submit]").first().click();
  await expect(page).toHaveURL(/\/app$/);
}

// Changes the signed-in user's saved locale, the same call the language switcher makes.
export async function setLocale(page: Page, locale: "fr" | "en" | "es" | "ar") {
  await page.evaluate(async (value) => {
    const token = document.querySelector<HTMLMetaElement>("meta[name=csrf-token]")!.content;
    await fetch("/locale", {
      method: "PATCH",
      headers: { "X-CSRF-Token": token, "Content-Type": "application/x-www-form-urlencoded" },
      body: `locale=${value}`,
    });
  }, locale);
}

// Pages must fit the viewport: horizontal scrolling on a phone is always a layout bug.
export async function expectNoHorizontalOverflow(page: Page) {
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
  expect(overflow, "page is wider than the viewport").toBeLessThanOrEqual(1);
}
