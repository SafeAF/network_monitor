# frozen_string_literal: true

class DevicesController < ApplicationController
  def index
    @devices = Device.order(:ip)
  end

  def update
    device = Device.find(params[:id])
    device.update!(device_params)
    redirect_to devices_path
  end

  private

  def device_params
    params.require(:device).permit(:name, :notes)
  end
end
