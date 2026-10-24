require "test_helper"
require "csv"
require "zip"

class ReportSpreadsheetTest < ActiveSupport::TestCase
  test "CSV preserves UTF8 Arabic and quotes formula-like text while retaining numeric cells" do
    values = [ "متجر الرباط", "=1+1", "+SUM(A1)", "-42", "@SUM(A1)", " \t=1", "\ttext", "\rtext", "\ntext", "a,\"b\"\nc", -42, 95 ]
    csv = Reports::Spreadsheet.new(headers: [ "المتجر" ], rows: [ values ]).csv
    assert csv.start_with?("\uFEFF")
    assert csv.valid_encoding?
    rows = CSV.parse(csv.delete_prefix("\uFEFF"))
    assert_equal [ "المتجر" ], rows.first
    assert_equal values.first, rows.last.first
    (1..8).each { |index| assert_equal "'#{values[index]}", rows.last[index] }
    assert_equal values[9], rows.last[9]
    assert_equal [ "-42", "95" ], rows.last.last(2)
    [ "\uFEFF=1", "\u200B@SUM(A1)", "\u0000+1" ].each do |value|
      content = Reports::Spreadsheet.new(headers: [], rows: [ [ value ] ]).csv
      assert_equal "'#{value}", CSV.parse(content.delete_prefix("\uFEFF")).last.first
    end
  end

  test "XLSX has linked workbook parts, literal escaped formula text, typed numbers and RTL Arabic" do
    sheet = Reports::Spreadsheet.new(headers: [ "المتجر", "النتيجة", "صيغة" ], rows: [ [ "<متجر> & \"اسم\"\u0000", 75, "=HYPERLINK(\"https://example.test\")" ] ])
    data = I18n.with_locale(:ar) { sheet.xlsx }
    Zip::File.open_buffer(data) do |zip|
      assert_equal %w[[Content_Types].xml _rels/.rels xl/_rels/workbook.xml.rels xl/workbook.xml xl/worksheets/sheet1.xml].sort, zip.entries.map(&:name).sort
      zip.entries.each do |entry|
        document = Nokogiri::XML(zip.read(entry)) { |config| config.strict }
        assert_empty document.errors
      end
      types = Nokogiri::XML(zip.read("[Content_Types].xml"))
      assert_equal "/xl/worksheets/sheet1.xml", types.at_xpath("//*[local-name()='Override'][@PartName='/xl/worksheets/sheet1.xml']")["PartName"]
      workbook = Nokogiri::XML(zip.read("xl/workbook.xml"))
      assert_equal "rId1", workbook.at_xpath("//*[local-name()='sheet']")["r:id"]
      relations = Nokogiri::XML(zip.read("xl/_rels/workbook.xml.rels"))
      assert_equal "worksheets/sheet1.xml", relations.at_xpath("//*[local-name()='Relationship'][@Id='rId1']")["Target"]
      xml = Nokogiri::XML(zip.read("xl/worksheets/sheet1.xml"))
      xml.remove_namespaces!
      assert_equal "1", xml.at_xpath("//sheetView")["rightToLeft"]
      assert_empty xml.xpath("//f")
      assert_equal "inlineStr", xml.at_xpath("//c[@r='C2']")["t"]
      assert_equal '=HYPERLINK("https://example.test")', xml.at_xpath("//c[@r='C2']//t").text
      assert_equal '<متجر> & "اسم"', xml.at_xpath("//c[@r='A2']//t").text
      assert_equal "n", xml.at_xpath("//c[@r='B2']")["t"]
      assert_equal "75", xml.at_xpath("//c[@r='B2']/v").text
    end
  end
end
