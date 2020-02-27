==title==
Writing an SSDP Directory in Elixir

==tags==
elixir

==body==
I used to spend all of my free time programming random toy projects. Over time, likely after spending a few years in industry, I started to spend so much time thinking about how to write maintainable code that I think I started to lose out on what makes programming fun: exploring new ideas and learning how to do things I've never done before. I'd like to rediscover that joy, and to do that, I need to stop being so much of a perfectionist.

I think that in an office setting, deadlines force me to move on and call things done, but in my personal life, lack of that kind of pressure means that I can spend literally forever architecting and rearchitecting the same piece of code until it's perfect (it never is).

To fix this, I'm going to try blogging! If I can make myself excited to share my code with other people, imperfect and unfinished as it is, then maybe I can start to unlearn the paralysis that's been plaguing me for the past few years.

To start, I just want to walk through a small program I wrote a few months ago. I wanted to learn how [SSDP](https://en.wikipedia.org/wiki/Simple_Service_Discovery_Protocol) works, so I implemented an SSDP Directory! For those of you who aren't aware, SSDP is a fairly simple protocol from the 90s that's used to facilitate the discovery of network services. Nowadays, it's also used by everything from smart TVs to Hue lights.

My implementation can be found [here](https://github.com/QuinnWilton/ssdp_directory), and the (very readable!) RFC is [here](https://tools.ietf.org/html/draft-cai-ssdp-v1-03).

If I run the application, it discovers all of the devices on my network:

```elixir
iex(1)> SSDPDirectory.list_services
%{
  "uuid:b236f169-9c9d-db64-ffff-ffffcff91970::upnp:rootdevice" => %SSDPDirectory.Service{
    location: "http://192.168.0.150:60000/upnp/dev/b236f169-9c9d-db64-ffff-ffffcff91970/desc",
    type: "upnp:rootdevice",
    usn: "uuid:b236f169-9c9d-db64-ffff-ffffcff91970::upnp:rootdevice"
  },
  ...
}
```

The key to SSDP is what's called [multicast addressing](https://en.wikipedia.org/wiki/Multicast). Essentially, services broadcast their presence to a specially designated multicast address, and then anyone else on the network is able to listen for those presence notifications in order to track the appearance and disappearance of new services.

Fortunately, Elixir, my language of choice, makes subscribing to these notifications [easy](https://github.com/QuinnWilton/ssdp_directory/blob/master/lib/ssdp_directory/multicast_channel.ex)!

```elixir
defmodule SSDPDirectory.MulticastChannel do
  use GenServer

  alias __MODULE__

  alias SSDPDirectory.{
    Discovery,
    Presence
  }

  @multicast_group {239, 255, 255, 250}
  @multicast_port 1900

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @spec broadcast(GenServer.name(), iodata) :: :ok
  def broadcast(channel \\ MulticastChannel, packet) do
    GenServer.cast(channel, {:broadcast, packet})
  end

  @spec init(:ok) :: {:ok, %{socket: port}}
  def init(:ok) do
    udp_options = [
      :binary,
      active: true,
      add_membership: {@multicast_group, {0, 0, 0, 0}},
      multicast_if: {0, 0, 0, 0},
      multicast_loop: false,
      reuseaddr: true
    ]

    {:ok, socket} = :gen_udp.open(@multicast_port, udp_options)

    {:ok, %{socket: socket}}
  end

  def handle_cast({:broadcast, packet}, state) do
    :ok = :gen_udp.send(state.socket, @multicast_group, @multicast_port, packet)

    {:noreply, state}
  end

  def handle_info({:udp, _socket, _ip, _port, data}, state) do
    Task.Supervisor.start_child(SSDPDirectory.DecodingSupervisor, fn ->
      with {:ok, packet, rest} <- :erlang.decode_packet(:http_bin, data, []),
           {:ok, handler} <- packet_handler(packet),
           {:ok, decoded} <- handler.decode(rest) do
        :ok = handler.handle(decoded)
      end
    end)

    {:noreply, state}
  end

  defp packet_handler({:http_request, "NOTIFY", _target, _version}),
    do: {:ok, Presence}

  defp packet_handler({:http_response, _version, 200, "OK"}),
    do: {:ok, Discovery.Response}

  defp packet_handler(_packet), do: :error
end
```

Most of the magic happens in the `init/1` function. By opening a UDP socket and joining it to the protocol's multicast group, our process is now able to receive packets that are broadcast to that group. That receiving logic is located in the `handle_info/2` function within the same file.

When receiving a packet, we spawn another process that is responsible for handling that packet. This process runs under a `Task.Supervisor` in order to isolate crashes of that process from the `MulticastChannel`. Also interesting, is that we're able to decode the incoming packets using [:erlang.decode_packet/3](http://erlang.org/doc/man/erlang.html#decode_packet-3). This is a builtin function that allows us to decode a variety of packet formats, piece-by-piece. In this case, we're using it to parse the packet as an HTTP packet. This is the same way that Elixir's [Mint](https://github.com/elixir-mint/mint/blob/master/lib/mint/http1/response.ex#L7) decodes HTTP responses too!

Based on the type of packet decoded, `packet_handler/1` then delegates the handling of that packet to another module. Either we've received an HTTP NOTIFY request, and we're dealing with a [presence notification](https://github.com/QuinnWilton/ssdp_directory/blob/master/lib/ssdp_directory/presence.ex), or we've received a [response to a discovery request](https://github.com/QuinnWilton/ssdp_directory/blob/master/lib/ssdp_directory/discovery/response.ex).

Let's take a look at the presence case. In case you're curious, here's an example presence notification:

```elixir
NOTIFY * HTTP/1.1
Host: 239.255.255.250:reservedSSDPport
NT: blenderassociation:blender
NTS: ssdp:alive
USN: someunique:idscheme3
AL: <blender:ixl><http://foo/bar>
Cache-Control: max-age = 7393
```

And here's where we handle it:

```elixir
defmodule SSDPDirectory.Presence do
  require Logger

  alias __MODULE__
  alias SSDPDirectory.HTTP

  @type command :: Presence.Alive.t() | Presence.ByeBye.t()

  @spec decode(binary) ::
          :error
          | {:ok, command}
  def decode(data) do
    case HTTP.decode_headers(data, []) do
      {:ok, headers, _rest} ->
        process_headers(headers)

      :error ->
        _ = Logger.debug(fn -> "Failed to decode NOTIFY request: " <> inspect(data) end)

        :error
    end
  end

  @spec handle(command) :: :ok
  def handle(%Presence.Alive{} = command) do
    Presence.Alive.handle(command)
  end

  def handle(%Presence.ByeBye{} = command) do
    Presence.ByeBye.handle(command)
  end

  defp process_headers(headers) do
    do_process_headers(headers, %{})
  end

  defp do_process_headers([], args) do
    case args do
      %{command: "ssdp:alive", usn: usn, type: type}
      when not is_nil(usn) and not is_nil(type) ->
        {:ok,
         %Presence.Alive{
           usn: usn,
           type: type,
           location: Map.get(args, :location)
         }}

      %{command: "ssdp:byebye", usn: usn, type: type}
      when not is_nil(usn) and not is_nil(type) ->
        {:ok,
         %Presence.ByeBye{
           usn: usn,
           type: type
         }}

      _ ->
        :error
    end
  end

  defp do_process_headers([{"nts", command} | rest], args) do
    args = Map.put(args, :command, command)

    do_process_headers(rest, args)
  end

  defp do_process_headers([{"nt", type} | rest], args) do
    args = Map.put(args, :type, type)

    do_process_headers(rest, args)
  end

  defp do_process_headers([{"usn", usn} | rest], args) do
    args = Map.put(args, :usn, usn)

    do_process_headers(rest, args)
  end

  defp do_process_headers([{"al", location} | rest], args) do
    args = Map.put(args, :location, location)

    do_process_headers(rest, args)
  end

  defp do_process_headers([{"location", location} | rest], args) do
    args = Map.put(args, :location, location)

    do_process_headers(rest, args)
  end

  defp do_process_headers([_ | rest], args) do
    do_process_headers(rest, args)
  end
end
```

It looks like there's a lot going on here, but it's actually pretty simple. Starting in `decode/1`, we continue decoding the packet from `MulticastChannel`. This time it's the headers we're interested in, so we decode those, and then process them in order to determine what kind of command we're dealing with.

The processing step simply involves recursing over the list of headers, and accumulating the relevant ones in a map . Once we've done that, we just construct the corresponding command!

Lastly, the command handler delegates to a third module based on the type of command being processed. For example, in the case of an [ssdp:alive](https://github.com/QuinnWilton/ssdp_directory/blob/master/lib/ssdp_directory/presence/alive.ex) command:

```elixir
defmodule SSDPDirectory.Presence.Alive do
  require Logger

  alias __MODULE__

  alias SSDPDirectory.{
    Cache,
    Service
  }

  @enforce_keys [:usn, :type]
  defstruct [:location] ++ @enforce_keys

  @type t :: %Alive{}

  @spec handle(Alive.t()) :: :ok
  def handle(%Alive{} = command) do
    _ = Logger.debug(fn -> "Handling ssdp:alive request: " <> inspect(command) end)

    service = %Service{
      usn: command.usn,
      type: command.type,
      location: command.location
    }

    :ok = Cache.insert(service)
  end
end
```

Here we just construct a service using the parameters in the command, and then store it in our [cache](https://github.com/QuinnWilton/ssdp_directory/blob/master/lib/ssdp_directory/cache.ex):

```elixir
defmodule SSDPDirectory.Cache do
  use GenServer

  require Logger

  alias __MODULE__
  alias SSDPDirectory.Service

  def start_link(opts \\ []) do
    GenServer.start_link(Cache, :ok, opts)
  end

  def contents(cache \\ Cache) do
    :ets.tab2list(cache)
    |> Enum.into(%{})
  end

  def insert(cache \\ Cache, %Service{} = service) do
    GenServer.call(cache, {:insert, service})
  end

  def delete(cache \\ Cache, %Service{} = service) do
    GenServer.call(cache, {:delete, service})
  end

  def flush(cache \\ Cache) do
    GenServer.call(cache, :flush)
  end

  def init(:ok) do
    table = :ets.new(Cache, [:named_table, read_concurrency: true])

    {:ok, %{table: table}}
  end

  def handle_call({:insert, %Service{usn: usn} = service}, _from, data) when not is_nil(usn) do
    :ets.insert(data.table, {usn, service})

    _ = Logger.debug(fn -> "Cached service: " <> inspect(usn) end)

    {:reply, :ok, data}
  end

  def handle_call({:delete, %Service{usn: usn}}, _from, data) when not is_nil(usn) do
    :ets.delete(data.table, usn)

    _ = Logger.debug(fn -> "Evicted service: " <> inspect(usn) end)

    {:reply, :ok, data}
  end

  def handle_call(:flush, _from, data) do
    :ets.delete_all_objects(data.table)

    _ = Logger.debug(fn -> "Flushed cache" end)

    {:reply, :ok, data}
  end
end
```

For the cache, I use an ETS table with `read_concurrency` enabled. Calling `Cache.contents/1` returns all of the services stored in the table, which more or less brings us back to where we started! There's a few other modules for handling different commands in the protocol, and for initiating discovery requests, but for the most part, it isn't a very complicated application!

As I often am when I code in Elixir, I was really surprised at how easy the language made doing things like joining the multicast group, and then asynchronously decoding any packets sent to the socket. I think the whole application took me about 3 hours to write, which I attribute more to the Erlang VM giving me really powerful tools than I do anything else. And that's even taking into account my incredibly verbose coding style -- I throw types and structs around like it's Haskell -- you could probably do the same thing in a terse 100 lines or so.

In a way, I'm writing more for myself than anything, and I don't know if this sort of blog post is interesting to anyone else, so if you've read this far, thanks for sticking with me :)