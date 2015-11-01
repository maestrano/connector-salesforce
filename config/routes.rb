Rails.application.routes.draw do
  maestrano_routes

  get 'home/index' => 'home#index'
  post 'home/synchronize' => 'home#synchronize'

  match 'auth/:provider/callback', to: 'sessions#create_omniauth', via: [:get, :post]
  match 'auth/failure', to: redirect('/'), via: [:get, :post]
  match 'signout_omniauth', to: 'sessions#destroy_omniauth', as: 'signout_omniauth', via: [:get, :post]
  match 'signout', to: 'sessions#destroy', as: 'signout', via: [:get, :post]

  root 'home#index'
end