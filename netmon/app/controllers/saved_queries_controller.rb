# frozen_string_literal: true

class SavedQueriesController < ApplicationController
  def create
    saved = SavedQuery.create!(
      name: params[:name].to_s.strip.presence || "Saved Query",
      path: params[:path].to_s,
      params_json: params[:params_json].to_s
    )

    redirect_to saved.path + query_string(saved.params_hash)
  end

  private

  def query_string(params_hash)
    return "" if params_hash.blank?

    "?" + params_hash.to_query
  end
end
