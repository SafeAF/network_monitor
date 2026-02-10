# frozen_string_literal: true

class RemoteHost < ApplicationRecord
  NEW_WINDOW = 60.seconds

  validates :ip, presence: true, uniqueness: true
  validates :tag, inclusion: { in: %w[unknown known_good suspicious] }

  has_many :remote_host_ports, dependent: :destroy

  def new?(now: Time.current, window: NEW_WINDOW)
    return false if first_seen_at.nil?

    first_seen_at >= now - window
  end

  def seen_age(now: Time.current)
    return "unknown" if first_seen_at.nil?

    seconds = (now - first_seen_at).to_i
    return "0s" if seconds <= 0

    if seconds < 60
      "#{seconds}s"
    elsif seconds < 3600
      "#{seconds / 60}m"
    elsif seconds < 86_400
      "#{seconds / 3600}h"
    else
      "#{seconds / 86_400}d"
    end
  end
end
