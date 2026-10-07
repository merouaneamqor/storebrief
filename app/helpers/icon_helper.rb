module IconHelper
  ICONS = %w[
    alert-triangle clock check-circle camera chevron-right message-circle
    trophy moon plus more-horizontal eye home send book inbox credit-card
  ].freeze

  TONE_ICONS = {
    "urgent" => "alert-triangle",
    "late" => "clock",
    "done" => "check-circle",
    "open" => "eye"
  }.freeze

  def icon(name, label: nil, css_class: "icon")
    key = name.to_s
    raise ArgumentError, "Unknown icon: #{key}" unless ICONS.include?(key)

    path = Rails.root.join("app/assets/images/icons/#{key}.svg")
    svg = File.read(path).strip
    classes = Array(css_class).join(" ")

    attrs = [ %(class="#{classes}") ]
    if label.present?
      attrs << %(role="img")
      attrs << %(aria-label="#{ERB::Util.html_escape(label)}")
    else
      attrs << %(aria-hidden="true")
    end

    svg = svg.sub(/\A<svg\b/, "<svg #{attrs.join(' ')}")
    svg.html_safe
  end

  def tone_icon(tone, label: nil)
    icon(TONE_ICONS.fetch(tone.to_s, "eye"), label: label, css_class: "icon icon--sm")
  end
end
