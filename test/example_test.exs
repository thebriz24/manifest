defmodule Example.Test do
  @moduledoc false
  use ExUnit.Case

  setup do
    token = "test_token"
    Application.put_env(:manifest, :auth_token, token)
    on_exit(fn -> Application.delete_env(:manifest, :auth_token) end)
    {:ok, pid} = Cache.start_link()
    [pid: pid, token: token]
  end

  test "example of success", %{pid: pid, token: token} do
    id = 5

    results =
      Manifest.new()
      |> Manifest.add_step(:cache_read, fn _ ->
        {:ok, :no_rollback, Cache.lookup(pid, token, id)}
      end)
      |> Manifest.add_step(:database_read, fn _ -> {:ok, :no_rollback, mock_lookup(id)} end)
      |> Manifest.add_step(
        :cache_put,
        fn %{database_read: %{id: id} = record} ->
          Cache.put(pid, token, id, record)
          {:ok, id}
        end,
        fn id ->
          Cache.delete(pid, token, id)
          {:ok, id}
        end
      )
      |> Manifest.perform()

    assert Agent.get(pid, & &1) == %{id => mock_lookup(id)}

    assert Manifest.digest(results) ==
             {:ok, %{cache_read: nil, database_read: mock_lookup(id), cache_put: id}}
  end

  test "example of rollback", %{pid: pid, token: token} do
    id = 5

    results =
      Manifest.new()
      |> Manifest.add_step(:cache_read, fn _ ->
        {:ok, :no_rollback, Cache.lookup(pid, token, id)}
      end)
      |> Manifest.add_step(:database_read, fn _ -> {:ok, :no_rollback, mock_lookup(id)} end)
      |> Manifest.add_step(
        :cache_put,
        fn %{database_read: %{id: id} = record} ->
          Cache.put(pid, token, id, record)
          {:ok, id}
        end,
        fn id ->
          Cache.delete(pid, token, id)
          {:ok, id}
        end
      )
      |> Manifest.add_step(:look_again, fn _ -> Cache.lookup(pid, "wrong_token", id) end)
      |> Manifest.perform()

    assert Agent.get(pid, & &1) == %{id => mock_lookup(id)}

    assert Manifest.digest(results) ==
             {:error, :look_again, :unauthenticated,
              %{cache_read: nil, database_read: mock_lookup(id), cache_put: id}}

    assert Manifest.rollback(results) == {:ok, %{cache_put: id}}
    assert Agent.get(pid, & &1) == %{}
  end

  defp mock_lookup(id) do
    %{id: id, content: "Anything"}
  end
end
