defmodule Cache do
  @moduledoc false
  use Agent

  def start_link() do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def lookup(pid, token, key) do
    do_if_authenticated(token, fn -> Agent.get(pid, fn state -> state[key] end) end)
  end

  def put(pid, token, key, value) do
    do_if_authenticated(token, fn -> Agent.update(pid, &Map.put(&1, key, value)) end)
  end

  def delete(pid, token, key) do
    do_if_authenticated(token, fn -> Agent.update(pid, &Map.delete(&1, key)) end)
  end

  def do_if_authenticated(token, function) do
    if authenticated?(token) do
      function.()
    else
      {:error, :unauthenticated}
    end
  end

  defp authenticated?(token) do
    Application.get_env(:manifest, :auth_token) == token
  end
end
