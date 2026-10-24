import { expect, test } from "@playwright/test";
import { expectNoHorizontalOverflow, setLocale, signIn } from "./helpers";

test.describe("HQ pages", () => {
  test.beforeEach(async ({ page }) => {
    await signIn(page, "hq");
    await setLocale(page, "fr");
  });

  for (const path of ["/visits", "/visits/calendar", "/vm_missions", "/playbooks", "/communications", "/checklists"]) {
    test(`${path} has one primary action in the page header`, async ({ page }) => {
      await page.goto(path);
      await expect(page.locator("header.radar-head a.btn--primary")).toHaveCount(1);
    });
  }

  test("an empty list explains itself and offers the next step", async ({ page }) => {
    await page.goto("/visits");
    const empty = page.locator(".empty-state");
    // The QA tenant has no visits unless a run planned one; a list is also a valid state.
    if (await empty.count()) {
      await expect(empty.locator(".empty-state__text")).not.toBeEmpty();
      await expect(empty.locator("a.btn--primary")).toHaveCount(1);
    } else {
      await expect(page.locator("table tbody tr").first()).toBeVisible();
    }
  });

  for (const locale of ["fr", "ar"] as const) {
    test(`checkbox lists keep the box at the ${locale} logical start`, async ({ page }) => {
      await setLocale(page, locale);
      await page.goto("/kb_articles/new");
      const row = page.locator("fieldset label:has(input[type=checkbox])").first();
      const box = await row.locator("input[type=checkbox]").boundingBox();
      const text = await row.boundingBox();
      expect(box && text).toBeTruthy();
      // Inline controls follow the writing direction, including saved Arabic locales.
      const startInset = locale === "ar"
        ? text!.x + text!.width - box!.x - box!.width
        : box!.x - text!.x;
      expect(startInset).toBeGreaterThanOrEqual(-1);
      expect(startInset).toBeLessThan(24);
      expect(text!.height).toBeLessThan(60);
    });
  }

  test("the comment composer is folded until opened", async ({ page }) => {
    await page.goto("/communications");
    // The sidebar also links to /communications/new, so look only inside the page body.
    await page.locator("main a[href^='/communications/']:not([href$='/new']):not([href$='/edit'])").first().click();
    const fold = page.locator("details.delivery-comments__compose-wrap").first();
    await expect(fold).toBeVisible();
    await expect(fold.locator("textarea")).toBeHidden();
    await fold.locator("summary").click();
    await expect(fold.locator("textarea")).toBeVisible();
  });

  test("knowledge base search is laid out as one filter row", async ({ page }) => {
    await page.goto("/kb_articles");
    const input = page.locator(".kb-search-form input[type=search]");
    const select = page.locator(".kb-search-form select");
    const submit = page.locator(".kb-search-form input[type=submit], .kb-search-form button[type=submit]").first();
    const [i, s, b] = await Promise.all([input.boundingBox(), select.boundingBox(), submit.boundingBox()]);
    expect(i && s && b).toBeTruthy();
    // Same row (tops within a few px) and a tappable height, not the browser default control.
    expect(Math.abs(i!.y - s!.y)).toBeLessThan(8);
    expect(Math.abs(s!.y - b!.y)).toBeLessThan(8);
    expect(i!.height).toBeGreaterThanOrEqual(40);
  });

  test("playbook store targets keep each checkbox next to its name", async ({ page }) => {
    await page.goto("/playbooks");
    const row = page.locator(".pb-targets__tree .check").first();
    await expect(row).toBeVisible();
    const box = await row.locator("input[type=checkbox]").boundingBox();
    const rowBox = await row.boundingBox();
    // A stacked checkbox makes the row two lines tall; inline rows stay compact.
    expect(rowBox!.height).toBeLessThan(48);
    expect(box!.y + box!.height).toBeLessThanOrEqual(rowBox!.y + rowBox!.height + 1);
  });

  test("reports store filter shows 'no match' only when nothing matches", async ({ page }) => {
    await page.goto("/reports");
    const message = page.locator("[data-reports-filter-target=empty]");
    await expect(message).toBeHidden();
    await page.locator(".report-search input").fill("zzzz-no-such-store");
    await expect(message).toBeVisible();
    await page.locator(".report-search input").fill("");
    await expect(message).toBeHidden();
  });

  test("the brief composer header is translated while the title is empty", async ({ page }) => {
    await page.goto("/communications/new");
    // The composer renders an edit bar and a hidden preview bar; the edit bar is the first.
    const topbar = page.locator("header.brief-topbar").first();
    await expect(topbar).toContainText("Brief sans titre");
    await expect(topbar).not.toContainText("Untitled");
  });

  test("main pages fit the viewport", async ({ page }) => {
    for (const path of ["/app", "/visits", "/playbooks", "/kb_articles", "/audit_history", "/reports"]) {
      await page.goto(path);
      await expectNoHorizontalOverflow(page);
    }
  });
});

test.describe("Area manager", () => {
  test("the store table sits in a card under its label", async ({ page }) => {
    await signIn(page, "area");
    const panel = page.locator(".area-stores.panel");
    await expect(panel).toBeVisible();
    await expect(panel.locator(".section-title")).toBeVisible();
    await expect(panel.locator("table.area-store-table")).toBeVisible();
  });
});

test.describe("Store on a phone", () => {
  test.use({ viewport: { width: 390, height: 844 } });

  test("inbox and today fit the screen and keep the tab bar reachable", async ({ page }) => {
    await signIn(page, "store");
    for (const path of ["/app", "/inbox", "/newsfeed", "/my_tasks"]) {
      await page.goto(path);
      await expectNoHorizontalOverflow(page);
    }
    await expect(page.locator(".app-bottom-nav")).toBeVisible();
  });

  test("the tab bar reaches My tasks", async ({ page }) => {
    await signIn(page, "store");
    const tab = page.locator(".app-bottom-nav a[href='/my_tasks']");
    await expect(tab).toBeVisible();
    await tab.click();
    await expect(page).toHaveURL(/\/my_tasks/);
    await expect(page.locator(".app-bottom-nav a.is-active")).toContainText(/.+/);
  });

  test("a store user never sees HQ actions in an empty state", async ({ page }) => {
    await signIn(page, "store");
    await page.goto("/newsfeed");
    const empty = page.locator(".empty-state");
    if (await empty.count()) {
      await expect(empty.locator("a.btn")).toHaveCount(0);
    }
  });
});

test.describe("Arabic (RTL)", () => {
  test.afterAll(async ({ browser }) => {
    // Put the shared QA user back on French so other runs see the default.
    const page = await browser.newPage();
    await signIn(page, "hq");
    await setLocale(page, "fr");
    await page.close();
  });

  test("the layout mirrors and header actions move to the far side", async ({ page }) => {
    await signIn(page, "hq");
    await setLocale(page, "ar");
    await page.goto("/visits");
    await expect(page.locator("html")).toHaveAttribute("dir", "rtl");
    const title = await page.locator("header.radar-head h1").boundingBox();
    const action = await page.locator("header.radar-head a.btn--primary").boundingBox();
    // In RTL the title block starts on the right, so actions sit to its left.
    expect(action!.x).toBeLessThan(title!.x);
    await expectNoHorizontalOverflow(page);
  });
  test("the closed navigation drawer stays off screen on a phone", async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    await signIn(page, "hq");
    await setLocale(page, "ar");
    await page.goto("/visits");
    const sidebar = page.locator("#app-sidebar");
    // Closed: entirely beyond the right edge (the inline-start edge in RTL).
    expect((await sidebar.boundingBox())!.x).toBeGreaterThanOrEqual(390);
    await page.locator(".app-menu-btn").click();
    // The drawer slides in over 200ms, so wait for it to settle inside the viewport.
    await expect.poll(async () => (await sidebar.boundingBox())!.x + (await sidebar.boundingBox())!.width).toBeLessThanOrEqual(391);
    expect((await sidebar.boundingBox())!.x).toBeGreaterThan(0);
  });
});
