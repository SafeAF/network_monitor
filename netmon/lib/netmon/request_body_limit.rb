# frozen_string_literal: true

require "json"
require "stringio"

module Netmon
  class RequestBodyLimit
    MAX_BYTES = 4 * 1024 * 1024

    def initialize(app)
      @app = app
    end

    def call(env)
      return too_large if env["CONTENT_LENGTH"].to_i > MAX_BYTES
      if (input = env["rack.input"])
        body = input.read(MAX_BYTES + 1) || ""
        return too_large if body.bytesize > MAX_BYTES
        env["rack.input"] = StringIO.new(body)
        env["CONTENT_LENGTH"] = body.bytesize.to_s
      end
      @app.call(env)
    end

    private

    def too_large
      body = JSON.generate(protocol_version: 1, error: "payload_too_large", retryable: false)
      [413, { "content-type" => "application/json", "content-length" => body.bytesize.to_s }, [body]]
    end
  end
end
