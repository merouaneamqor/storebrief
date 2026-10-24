Given("a Moroccan retail brand with an HQ user and a store user") do
  @brand = build_brand("atlas-ui", store_locale: "fr")
  @brand.hq.update!(locale: "fr")
end

Given("I am signed in as the HQ user") do
  log_in(@brand.hq)
end

Given("I am signed in as the store user") do
  log_in(@brand.store_user)
end

When("I open the {string} page") do |name|
  visit page_path(name)
end

When("I open the brief composer") do
  visit new_communication_path
end

Then("the page header has exactly one primary action") do
  page.assert_selector("header.radar-head a.btn--primary", count: 1)
end

Then("I see an empty state saying {string}") do |text|
  page.assert_selector(".empty-state .empty-state__text", text: text)
end

Then("I see an empty state") do
  page.assert_selector(".empty-state", count: 1)
end

Then("the empty state offers the action {string}") do |label|
  page.assert_selector(".empty-state a.btn--primary", text: label)
end

Then("the empty state offers no action") do
  page.assert_no_selector(".empty-state a.btn")
end

Then("the {string} message is hidden") do |_name|
  page.assert_selector("p.empty[data-reports-filter-target='empty']", visible: :hidden)
  page.assert_no_selector("p.empty[data-reports-filter-target='empty']", visible: :visible)
end

Then("the composer header reads {string}") do |title|
  page.assert_selector(".brief-topbar", text: title)
end
