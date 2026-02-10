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
  resources :devices, only: [:index, :update]
  get "anomalies" => "anomalies#index"
  get "remote_hosts" => "remote_hosts#index"
  get "remote_hosts/:ip" => "remote_hosts#show", constraints: { ip: /[^\/]+/ }
  get "remote_hosts/:ip/traceroute" => "remote_hosts#traceroute", constraints: { ip: /[^\/]+/ }, defaults: { format: :json }
end
