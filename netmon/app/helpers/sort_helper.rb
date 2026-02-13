# frozen_string_literal: true

module SortHelper
  def sortable_th(label, sort_key)
    current_sort = params[:sort].to_s
    current_dir = params[:dir].to_s == "asc" ? "asc" : "desc"
    next_dir = current_sort == sort_key && current_dir == "desc" ? "asc" : "desc"
    arrow = if current_sort == sort_key
              current_dir == "asc" ? "▲" : "▼"
            else
              ""
            end

    link_params = request.query_parameters.merge(sort: sort_key, dir: next_dir)
    link_to(
      [label, arrow].reject(&:blank?).join(" "),
      url_for(link_params),
      class: "text-cyan-200 hover:text-cyan-100"
    )
  end
end
