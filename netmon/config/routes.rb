Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "dashboard#index"
  get "dashboard/top_panels" => "dashboard#top_panels", defaults: { format: :json }

  get "connections" => "connections#index", defaults: { format: :json }
  get "metrics" => "metrics#index", defaults: { format: :json }
  get "metrics/series" => "metrics#series", defaults: { format: :json }
  get "system/series" => "system_metrics#series", defaults: { format: :json }
  get "drilldowns/new_dst" => "drilldowns#new_dst", defaults: { format: :json }
  get "drilldowns/unique_ports" => "drilldowns#unique_ports", defaults: { format: :json }
  get "drilldowns/new_asns" => "drilldowns#new_asns", defaults: { format: :json }
  get "drilldowns/rare_ports" => "drilldowns#rare_ports", defaults: { format: :json }
  resources :devices, only: [:index, :update]
  get "anomalies" => "anomalies#index"
  patch "anomalies/:id" => "anomalies#update"
  get "incidents" => "incidents#index"
  get "incidents/:id" => "incidents#show"
  post "incidents/:id/ack" => "incidents#ack"
  get "help" => "help#index"
  get "agent_events" => "agent_events#index"
  get "remote_hosts" => "remote_hosts#index"
  get "remote_hosts/:ip" => "remote_hosts#show", constraints: { ip: /[^\/]+/ }
  patch "remote_hosts/:ip" => "remote_hosts#update", constraints: { ip: /[^\/]+/ }
  get "remote_hosts/:ip/traceroute" => "remote_hosts#traceroute", constraints: { ip: /[^\/]+/ }, defaults: { format: :json }
  get "search" => "search#index"
  get "search/hosts" => "search#hosts"
  get "search/connections" => "search#connections"
  get "search/anomalies" => "search#anomalies"
  post "saved_queries" => "saved_queries#create"
  resources :allowlist_rules, only: [:create]
  resources :suppression_rules, only: [:create]

  namespace :api do
    namespace :v1 do
      namespace :netmon do
        post "events/batch" => "events#batch"
      end
    end
  end
end
