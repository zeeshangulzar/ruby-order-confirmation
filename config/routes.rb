Rails.application.routes.draw do
  root   "checkouts#new"
  post   "/checkout", to: "checkouts#create", as: :checkout
  get    "/success",  to: "checkouts#success", as: :success

  namespace :webhooks do
    post "stripe", to: "stripe#create"
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
