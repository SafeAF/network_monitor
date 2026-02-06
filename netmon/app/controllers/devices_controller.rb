# frozen_string_literal: true

class DevicesController < ApplicationController
  def index
    @devices = Device.order(:ip)
  end

  def update
    device = Device.find(params[:id])
    attrs = device_params.to_h
    name = attrs.fetch("name", "").to_s.strip
    attrs["name"] = device.ip if name.empty?
    device.update!(attrs)
    respond_to do |format|
      format.html { redirect_to devices_path }
      format.json { render json: { id: device.id, name: device.name } }
    end
  end

  private

  def device_params
    params.require(:device).permit(:name, :notes)
  end
end
