# frozen_string_literal: true

module Conntrack
  class Key
    def self.from_entry(entry)
      return nil if entry.nil? || entry.orig.nil?

      orig = entry.orig
      "#{entry.proto}|#{orig.src}|#{orig.sport}|#{orig.dst}|#{orig.dport}"
    end
  end
end
