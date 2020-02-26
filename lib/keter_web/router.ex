defmodule KeterWeb.Router do
  use KeterWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", KeterWeb do
    pipe_through :browser

    get "/", PageController, :index

    get "/blog", BlogController, :index
    get "/blog/:id", BlogController, :show
  end
end
