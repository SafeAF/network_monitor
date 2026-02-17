# frozen_string_literal: true

module Search
  class ParamNormalizer
    DEFAULT_PER = 50
    MAX_PER = 200

    def self.clean_string(value)
      value.to_s.strip.presence
    end

    def self.clean_downcase(value)
      clean_string(value)&.downcase
    end

    def self.clean_upcase(value)
      clean_string(value)&.upcase
    end

    def self.clean_int(value)
      return nil unless value.to_s.match?(/\A\d+\z/)

      value.to_i
    end

    def self.clean_bool(value)
      return nil if value.nil? || value.to_s.strip == ""

      %w[1 true yes].include?(value.to_s.downcase)
    end

    def self.clean_window(value)
      val = clean_string(value)
      return nil unless val

      val.match?(/\A\d+(m|h|d|w)\z/) ? val : nil
    end

    def self.page(value)
      page = clean_int(value) || 1
      page < 1 ? 1 : page
    end

    def self.per(value)
      per = clean_int(value) || DEFAULT_PER
      per = 1 if per < 1
      per = MAX_PER if per > MAX_PER
      per
    end
  end
end
