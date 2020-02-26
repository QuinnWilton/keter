defmodule KeterWeb.BlogController do
  use KeterWeb, :controller

  alias Keter.Blog

  def index(conn, _params) do
    posts = Blog.list_posts()

    render(conn, "index.html", posts: posts, page_title: "Quinn's Blog")
  end

  def show(conn, %{"id" => id}) do
    post = Blog.get_post_by_id!(id)

    render(conn, "show.html", post: post, page_title: "Quinn's Blog - #{post.title}")
  end
end
