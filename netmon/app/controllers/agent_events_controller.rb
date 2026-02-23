class AgentEventsController < ApplicationController
  DEFAULT_PER_PAGE = 100

  def index
    @page = params[:page].to_i
    @page = 1 if @page < 1
    @per_page = DEFAULT_PER_PAGE

    scope = NetmonEvent.all
    scope = scope.where(event_type: params[:event_type]) if params[:event_type].present?
    scope = scope.where(router_id: params[:router_id]) if params[:router_id].present?
    if params[:since].present?
      since = Time.parse(params[:since]) rescue nil
      scope = scope.where("ts >= ?", since) if since
    end

    @total = scope.count
    @events = scope.order(ts: :desc).limit(@per_page).offset((@page - 1) * @per_page)

    @event_types = NetmonEvent.distinct.order(:event_type).pluck(:event_type)
    @router_ids = NetmonEvent.distinct.order(:router_id).pluck(:router_id)
  end
end
