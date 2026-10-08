module HqBoardHelper
  DASH_BLUE = "#2f7cf6"

  def hq_sparkline(points)
    values = Array(points).map(&:to_f)
    values = [ 0.0 ] if values.empty?
    values = [ values.first, values.first ] if values.one?
    width = 160.0
    height = 42.0
    pad_y = 4.0
    min, max = values.minmax
    coords = values.each_with_index.map do |value, index|
      x = index.to_f / (values.size - 1) * width
      y = if max == min
        height / 2
      else
        pad_y + (height - (pad_y * 2)) * (1 - ((value - min) / (max - min)))
      end
      [ x, y ]
    end
    line = svg_line(coords)
    area = "#{line} L#{coords.last[0].round(2)} #{height} L#{coords.first[0].round(2)} #{height} Z"
    tag.svg(class: "hq-spark", viewBox: "0 0 #{width} #{height}", preserveAspectRatio: "none", aria: { hidden: true }, focusable: "false") do
      safe_join([
        tag.path(d: area, fill: DASH_BLUE, opacity: "0.12"),
        tag.path(d: line, fill: "none", stroke: DASH_BLUE, "stroke-width": "2", "stroke-linecap": "round", "stroke-linejoin": "round", "vector-effect": "non-scaling-stroke")
      ])
    end
  end

  def hq_execution_chart(trend)
    return "".html_safe if trend.nil?

    values = trend.points.map(&:to_i)
    span = [ trend.span.to_i, 2 ].max
    max = hq_axis_max(values.max.to_i)
    width = 640
    height = 220
    left = 46
    right = 12
    top = 16
    plot_h = 150
    plot_w = width - left - right
    baseline = top + plot_h
    y_for = ->(value) { top + plot_h - ((value.to_f / max) * plot_h) }
    x_for = ->(index) { left + ((index.to_f / (span - 1)) * plot_w) }
    ticks = [ max, (max * 0.75).round, (max * 0.5).round, (max * 0.25).round, 0 ].uniq.sort.reverse

    parts = ticks.flat_map do |tick|
      y = y_for.call(tick).round(2)
      [
        tag.line(x1: left, y1: y, x2: left + plot_w, y2: y, stroke: "#e6edf5", "stroke-width": "1"),
        tag.text(tick, x: left - 8, y: y + 4, "text-anchor": "end", fill: "#94a3b8", "font-size": "12")
      ]
    end

    coords = values.each_with_index.map { |value, index| [ x_for.call(index), y_for.call(value) ] }
    parts << tag.path(d: svg_line(coords), fill: "none", stroke: DASH_BLUE, "stroke-width": "2.5", "stroke-linejoin": "round", "stroke-linecap": "round") if coords.size >= 2
    if values.uniq.size > 1
      coords.each do |x, y|
        parts << tag.circle(cx: x.round(2), cy: y.round(2), r: "3.4", fill: DASH_BLUE, stroke: "#fff", "stroke-width": "1.6")
      end
    end
    labels = hq_chart_labels(trend)
    labels.each_with_index do |(date, index), position|
      anchor = position.zero? ? "start" : (position == labels.size - 1 ? "end" : "middle")
      x = if position.zero?
        left
      elsif position == labels.size - 1
        left + plot_w
      else
        x_for.call(index)
      end
      parts << tag.text(hq_chart_day(date), x: x.round(2), y: baseline + 26, "text-anchor": anchor, fill: "#94a3b8", "font-size": "12")
    end

    tag.svg(class: "hq-chart", viewBox: "0 0 #{width} #{height}", role: "img", aria: { label: t("morocco.hq.execution") }) do
      safe_join(parts)
    end
  end

  def hq_month_range(trend)
    return if trend.nil?

    year = trend.to.year
    finish = I18n.locale == :en ? "#{hq_chart_day(trend.to)}, #{year}" : "#{hq_chart_day(trend.to)} #{year}"
    t("morocco.hq.range", from: hq_chart_day(trend.from), to: finish)
  end

  def hq_delta_text(delta)
    return if delta.nil?

    number = delta.abs
    number = number.to_i if (number - number.to_i).abs < 0.05
    t(delta.negative? ? "morocco.hq.delta_down" : "morocco.hq.delta_up", percent: number)
  end

  def hq_share(count, total)
    percent = total.to_i.zero? ? 0 : ((count.to_f / total) * 100).round
    t("morocco.hq.share", percent: percent)
  end

  private

  def hq_axis_max(value)
    value = value.to_i
    return 4 if value <= 4

    magnitude = 10**Math.log10(value).floor
    ((value.to_f / magnitude).ceil * magnitude).to_i
  end

  def hq_chart_day(date)
    month = I18n.l(date, format: "%b")
    I18n.locale == :en ? "#{month} #{date.day}" : "#{date.day} #{month}"
  end

  def hq_chart_labels(trend)
    span = [ trend.span.to_i, 1 ].max
    indexes = [ 0, (span * 0.5).round, span - 1 ].uniq
    indexes.map { |index| [ trend.from + index, index ] }
  end

  def svg_line(coords)
    coords.each_with_index.map { |(x, y), index| "#{index.zero? ? 'M' : 'L'}#{x.round(2)} #{y.round(2)}" }.join(" ")
  end
end
