require "test_helper"

class Vazivo::NewsfeedTest < ActiveSupport::TestCase
  test "pages news and announcements newest first for one store" do
    brand = build_brand("newsfeed-service", features: { morocco_ops: true })
    other = brand.tenant.org_units.create!(name: "Anfa", unit_type: "store", parent: brand.region)

    first = brand.tenant.communications.create!(
      author: brand.hq, title_fr: "One", body_fr: "a", format: "news", status: "draft"
    )
    first.send_to!([ brand.store.id ])
    first.update_columns(created_at: 3.days.ago)

    second = brand.tenant.communications.create!(
      author: brand.hq, title_fr: "Two", body_fr: "b", format: "announcement", status: "draft"
    )
    second.send_to!([ brand.store.id ])
    second.update_columns(created_at: 1.day.ago)

    task = brand.tenant.communications.create!(
      author: brand.hq, title_fr: "Task", body_fr: "c", format: "task", status: "draft"
    )
    task.send_to!([ brand.store.id ])

    foreign = brand.tenant.communications.create!(
      author: brand.hq, title_fr: "Foreign", body_fr: "d", format: "news", status: "draft"
    )
    foreign.send_to!([ other.id ])

    page1 = Vazivo::Newsfeed.for(store: brand.store, tenant: brand.tenant, page: 1, per_page: 1)
    assert_equal 2, page1.total_count
    assert_equal 2, page1.total_pages
    assert_equal 1, page1.page
    assert_equal [ second.id ], page1.deliveries.map { |d| d.communication_id }

    page2 = Vazivo::Newsfeed.for(store: brand.store, tenant: brand.tenant, page: 2, per_page: 1)
    assert_equal [ first.id ], page2.deliveries.map { |d| d.communication_id }
  end
end
