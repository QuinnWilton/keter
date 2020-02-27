defmodule KeterWeb.BlogController do
  use KeterWeb, :controller

  alias Keter.Blog

  def index(conn, params) do
    posts =
      case params do
        %{"tag" => tag} ->
          Blog.get_posts_by_tag!(tag)

        _ ->
          Blog.list_posts()
      end

    tags = Blog.list_tags()

    render(conn, "index.html", posts: posts, tags: tags, page_title: "Quinn's Blog")
  end

  def show(conn, %{"id" => id}) do
    post = Blog.get_post_by_id!(id)

    render(conn, "show.html", post: post, page_title: "Quinn's Blog - #{post.title}")
  end
end
