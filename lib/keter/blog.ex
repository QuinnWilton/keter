defmodule Keter.Blog do
  alias Keter.Blog.Post

  defmodule NotFoundError do
    defexception [:message, plug_status: 404]
  end

  posts_paths =
    "posts/**/*.md"
    |> Path.wildcard()
    |> Enum.sort()

  posts =
    for post_path <- posts_paths do
      @external_resource Path.relative_to_cwd(post_path)
      Post.parse!(post_path)
    end

  @posts Enum.sort_by(posts, & &1.date, {:desc, Date})
  @tags posts |> Enum.flat_map(& &1.tags) |> Enum.uniq() |> Enum.sort()

  def list_tags do
    @tags
  end

  def list_posts do
    @posts
  end

  def get_posts_by_tag!(tag) do
    case Enum.filter(list_posts(), &(tag in &1.tags)) do
      [] -> raise NotFoundError, "posts with tag=#{tag} not found"
      posts -> posts
    end
  end

  def get_post_by_id!(id) do
    case Enum.find(list_posts(), fn post -> post.id == id end) do
      nil -> raise NotFoundError, "post with id=#{id} not found"
      post -> post
    end
  end
end
