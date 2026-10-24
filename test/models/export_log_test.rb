require "test_helper"

class ExportLogTest < ActiveSupport::TestCase
  test "export metadata is tenant bound and append only" do
    brand = build_brand("export-log")
    foreign = build_brand("foreign-export-log")
    log = ExportLog.create!(tenant: brand.tenant, actor: brand.hq, source: "reports", output_format: "csv", row_count: 3, filters: { from: "2026-01-01" })
    assert_raises(ActiveRecord::ReadOnlyRecord) { log.update!(row_count: 4) }
    invalid = ExportLog.new(tenant: brand.tenant, actor: foreign.hq, source: "reports", output_format: "xlsx", row_count: 0)
    assert_not invalid.valid?
    assert invalid.errors.of_kind?(:actor, :invalid)
  end
end
