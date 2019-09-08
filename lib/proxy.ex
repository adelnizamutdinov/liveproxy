defmodule Proxy do
  @type proxy :: {String.t(), port}
  @type type :: :http | :socks
  @type req :: {proxy, type}
  @type resp :: {type, String.t()} | :err

  @spec to_option(req) :: {:proxy, any}
  defp to_option({proxy, :http}), do: {:proxy, proxy}
  defp to_option({{host, port}, :socks}), do: {:proxy, {:socks5, to_charlist(host), port}}

  @spec check_type(req) :: resp
  defp check_type({{host, _port}, type} = req) do
    opts = [to_option(req)]

    case :hackney.request(:get, "https://adel.lol", [], "", opts) do
      {:ok, 200, _headers, _client} ->
        %{country: %{country: %{name: country}}} = Geolix.lookup(host)
        {type, country}

      _ ->
        :err
    end
  end

  @timeout 15_000

  @spec check(proxy) :: resp
  def check(proxy) do
    parent = self()

    {:ok, _} = Task.start(fn -> send(parent, check_type({proxy, :http})) end)
    {:ok, _} = Task.start(fn -> send(parent, check_type({proxy, :socks})) end)

    receive do
      :err ->
        receive do
          x -> x
        after
          @timeout -> :err
        end

      x ->
        x
    after
      @timeout -> :err
    end
  end

  @spec parse_list(String.t()) :: [proxy]
  def parse_list(list) do
    String.split(list, "\n", trim: true)
    |> Enum.flat_map(fn line ->
      with [host, port_s] <- String.split(line, ":", trim: true),
           {port, _} <- Integer.parse(port_s) do
        [{host, port}]
      else
        _ -> []
      end
    end)
  end
end
