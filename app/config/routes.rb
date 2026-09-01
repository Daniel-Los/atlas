Rails.application.routes.draw do
  mount RailsIcons::Engine, at: '/rails_icons'
  mount Rswag::Ui::Engine  => "/api-docs"
  mount Rswag::Api::Engine => "/api-docs"
  mount ActionCable.server => "/cable"

  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      get  :search,         to: "search#index"
      get  :reverse,        to: "reverse#show"
      post "reverse/batch", to: "reverse#batch"
      get  :route,          to: "routes#show"
      get  :transit,        to: "transits#show"
      get  "whats-here",    to: "whats_here#index"
      get  :pois,           to: "pois#index"
      get  "pois/categories", to: "pois#categories"
      get  :geocode,        to: "geocode#index"
    end
  end

  namespace :admin do
    get  :services,                  to: "services#index"
    post "services/:name",           to: "services#update",          as: :service
    get  "services/:name/logs",      to: "services#logs",            as: :service_logs
    post "services/:name/update",    to: "services#update_now",      as: :service_update
    patch "services/:name/schedule", to: "services#schedule_update", as: :service_schedule
    patch "services/:name/autoupdate", to: "services#toggle_auto",   as: :service_toggle_auto
    post :regions,               to: "regions#update"
    post :apply,                 to: "apply#create"
    get  :tiles,                 to: "tiles#show"
    post "tiles/download",       to: "tiles#download",  as: :tiles_download
    patch :tiles,                to: "tiles#update"
    patch "tiles/theme",         to: "tiles#update_theme", as: :tiles_theme
  end

  get "static_map", to: "static_maps#show", as: :static_map

  root "home#index"
end
