# frozen_string_literal: true

class SavedQueriesController < ApplicationController
  def create
    saved = SavedQuery.new(
      name: params[:name].to_s.strip.presence || "Saved Query",
      path: params[:path].to_s,
      params_json: params[:params_json].to_s,
      kind: resolve_kind
    )

    unless saved.save
      return render plain: saved.errors.full_messages.join(", "), status: :unprocessable_entity
    end

    redirect_to saved.path + query_string(saved.params_hash)
  end

  private

  def query_string(params_hash)
    return "" if params_hash.blank?

    "?" + params_hash.to_query
  end

  def resolve_kind
    kind = params[:kind].to_s
    return kind if SavedQuery::KINDS.include?(kind)

    path = params[:path].to_s
    return "hosts" if path.include?("/search/hosts")
    return "connections" if path.include?("/search/connections")
    return "anomalies" if path.include?("/search/anomalies")

    "hosts"
  end
  private :resolve_kind
end
