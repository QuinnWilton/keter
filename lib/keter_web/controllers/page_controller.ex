defmodule KeterWeb.PageController do
  use KeterWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end
end
