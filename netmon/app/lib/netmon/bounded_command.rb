# frozen_string_literal: true

require "open3"

module Netmon
  class BoundedCommand
    # Read incrementally, bound memory, and always terminate/reap the child.
    # Cancellation is checked while the process is running, not just in the UI.
    def self.capture(*command, timeout:, cancelled: -> { false }, max_bytes: 65_536)
      result = nil
      Open3.popen2e(*command) do |stdin, stdout, child|
        stdin.close
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
        output = +""
        eof = false
        begin
          loop do
            break if cancelled.call || Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

            if eof
              if child.join(0.1)
                result = output if child.value.success?
                break
              end
            elsif IO.select([stdout], nil, nil, 0.1)
              chunk = stdout.read_nonblock(4096, exception: false)
              if chunk.nil?
                eof = true
                next
              end
              next if chunk == :wait_readable

              output << chunk
              break if output.bytesize > max_bytes
            end
          end
        ensure
          if child.alive?
            terminate(child.pid, "TERM")
            unless child.join(0.2)
              terminate(child.pid, "KILL")
              child.join
            end
          end
        end
      end
      result
    rescue Errno::ENOENT
      nil
    end

    def self.terminate(pid, signal)
      Process.kill(RUBY_PLATFORM.match?(/mswin|mingw/) ? "KILL" : signal, pid)
    rescue Errno::ESRCH
      # The process exited between the liveness check and signal delivery.
    end
    private_class_method :terminate
  end
end
