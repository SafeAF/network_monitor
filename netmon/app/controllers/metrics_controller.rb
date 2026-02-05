# frozen_string_literal: true

class MetricsController < ApplicationController
  def index
    render json: Netmon::Metrics.read
  end
end
