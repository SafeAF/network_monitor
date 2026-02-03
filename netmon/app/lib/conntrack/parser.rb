# frozen_string_literal: true

module Conntrack
  Tuple = Struct.new(:src, :dst, :sport, :dport, :packets, :bytes, keyword_init: true)
  Entry = Struct.new(
    :family,
    :proto,
    :timeout,
    :state,
    :orig,
    :reply,
    :flags,
    :mark,
    :use,
    keyword_init: true
  )

  class Parser
    def self.parse_line(line)
      return nil if line.nil?

      tokens = line.strip.split(/\s+/)
      return nil if tokens.empty?

      family = tokens[0]
      proto = tokens[2]
      timeout = tokens[4].to_i if tokens[4]

      state = nil
      idx = 5
      if tokens[idx] && !tokens[idx].include?("=") && !tokens[idx].start_with?("[")
        state = tokens[idx]
        idx += 1
      end

      orig = Tuple.new(src: nil, dst: nil, sport: nil, dport: nil, packets: 0, bytes: 0)
      reply = Tuple.new(src: nil, dst: nil, sport: nil, dport: nil, packets: 0, bytes: 0)

      current = orig
      src_count = 0
      flags = []
      mark = nil
      use = nil

      tokens[idx..].each do |token|
        if token.start_with?("[") && token.end_with?("]")
          flags << token.delete_prefix("[").delete_suffix("]")
          next
        end

        key, value = token.split("=", 2)
        next if value.nil?

        case key
        when "src"
          src_count += 1
          current = src_count >= 2 ? reply : orig
          current.src = value
        when "dst"
          current.dst = value
        when "sport"
          current.sport = value.to_i
        when "dport"
          current.dport = value.to_i
        when "packets"
          current.packets = value.to_i
        when "bytes"
          current.bytes = value.to_i
        when "mark"
          mark = value.to_i
        when "use"
          use = value.to_i
        else
          # ignore unknown tokens like zone=
        end
      end

      return nil if orig.src.nil? || orig.dst.nil? || reply.src.nil? || reply.dst.nil?

      Entry.new(
        family:,
        proto:,
        timeout:,
        state:,
        orig:,
        reply:,
        flags:,
        mark:,
        use:
      )
    end
  end
end
