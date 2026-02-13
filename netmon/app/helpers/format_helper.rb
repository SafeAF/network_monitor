# frozen_string_literal: true

module FormatHelper
  def format_bytes(value)
    return "--" if value.nil?

    units = %w[B KiB MiB GiB TiB]
    number = value.to_f
    index = 0
    while number >= 1024 && index < units.length - 1
      number /= 1024
      index += 1
    end
    formatted = index.zero? ? number.round.to_i : number.round(1)
    "#{formatted} #{units[index]}"
  end

  def format_rate(bytes_per_min)
    return "--" if bytes_per_min.nil?

    "#{format_bytes(bytes_per_min)}/min"
  end
end
