# frozen_string_literal: true

module Netmon
  module IncidentFingerprint
    SUPPRESSED_CODES = ["NO_RDNS"].freeze

    def self.build(device_id:, dst_ip:, dst_port:, proto:, codes:, required_codes: nil, suppress_codes: SUPPRESSED_CODES)
      code_list = Array(codes).compact.map(&:to_s)
      code_list -= Array(suppress_codes).map(&:to_s)
      if required_codes.present?
        required = Array(required_codes).map(&:to_s)
        required_subset = code_list & required
        code_list = required_subset.presence || code_list
      end
      code_list = code_list.uniq.sort

      [
        device_id,
        dst_ip,
        dst_port,
        proto,
        code_list.join(",")
      ].join("|")
    end
  end
end
