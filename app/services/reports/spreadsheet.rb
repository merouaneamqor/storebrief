require "csv"
require "zip"

module Reports
  # A single worksheet with numeric cells and explicitly literal text cells.
  class Spreadsheet
    XLSX_TYPE = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet".freeze
    XMLNS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main".freeze

    def initialize(headers:, rows:)
      @headers = headers
      @rows = rows
    end

    def csv
      "\uFEFF" + CSV.generate(encoding: Encoding::UTF_8) do |csv|
        csv << @headers.map { |value| csv_cell(value) }
        @rows.each { |row| csv << row.map { |value| csv_cell(value) } }
      end
    end

    def xlsx
      # All strings are inlineStr, so Excel never evaluates them as formulas.
      worksheet = Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
        xml.worksheet(xmlns: XMLNS) do
          xml.sheetViews { xml.sheetView(workbookViewId: "0", rightToLeft: I18n.locale == :ar ? "1" : "0") }
          xml.sheetData do
            [ @headers, *@rows ].each_with_index do |row, index|
              xml.row(r: index + 1) do
                row.each_with_index do |value, column|
                  ref = "#{column_name(column)}#{index + 1}"
                  if value.is_a?(Numeric)
                    xml.c(r: ref, t: "n") { xml.v(value) }
                  else
                    xml.c(r: ref, t: "inlineStr") { xml.is { xml.t(xml_text(value), "xml:space" => "preserve") } }
                  end
                end
              end
            end
          end
        end
      end.to_xml
      parts = {
        "[Content_Types].xml" => '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>',
        "_rels/.rels" => '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
        "xl/workbook.xml" => %(<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="#{XMLNS}" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Vazivo" sheetId="1" r:id="rId1"/></sheets></workbook>),
        "xl/_rels/workbook.xml.rels" => '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>',
        "xl/worksheets/sheet1.xml" => worksheet
      }
      Zip::OutputStream.write_buffer do |zip|
        parts.each do |path, content|
          zip.put_next_entry(path)
          zip.write(content)
        end
      end.string
    end

    private

    def csv_cell(value)
      return value if value.is_a?(Numeric)

      text = value.to_s
      text.match?(/\A(?:[\p{Space}\p{Cf}\p{Cc}]*[=+\-@]|[\t\r\n])/) ? "'#{text}" : text
    end

    def xml_text(value)
      value.to_s.gsub(/[^\u0009\u000A\u000D\u0020-\uD7FF\uE000-\uFFFD\u{10000}-\u{10FFFF}]/, "")
    end

    def column_name(index)
      name = +""
      loop do
        name.prepend((65 + index % 26).chr)
        index = index / 26 - 1
        break if index.negative?
      end
      name
    end
  end
end
