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

  test "example of branching", %{pid: pid, token: token} do
    id = 5

    manifest =
      Manifest.new()
      |> Manifest.add_step(:cache_read, fn _ ->
        {:ok, :no_rollback, Cache.lookup(pid, token, id)}
      end)
      |> Manifest.add_branch(
        build_leafed_branch(
          :cache_read,
          Manifest.build_step(:database_read, fn _ -> {:ok, :no_rollback, mock_lookup(id)} end)
        )
      )
      |> Manifest.add_branch(
        build_leafed_branch(
          :cache_read,
          Manifest.build_step(
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
        )
      )

    assert manifest |> Manifest.perform() |> Manifest.digest() ==
             {:ok, %{cache_read: nil, database_read: mock_lookup(5), cache_put: 5}}

    assert Agent.get(pid, & &1) == %{id => mock_lookup(id)}

    assert manifest |> Manifest.perform() |> Manifest.digest() ==
             {:ok, %{cache_read: mock_lookup(id), leaf: nil}}

    assert Agent.get(pid, & &1) == %{id => mock_lookup(id)}
  end

  test "example of merge", %{pid: pid, token: token} do
    id = 5

    manifest =
      Manifest.new()
      |> Manifest.add_step(:cache_read, fn _ ->
        {:ok, :no_rollback, Cache.lookup(pid, token, id)}
      end)
      |> Manifest.merge(fn %{cache_read: cache} ->
        inner = Manifest.new()

        if is_nil(cache) do
          inner
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
        else
          inner
        end
      end)

    assert manifest |> Manifest.perform() |> Manifest.digest() ==
             {:ok, %{cache_read: nil, database_read: mock_lookup(5), cache_put: 5}}

    assert Agent.get(pid, & &1) == %{id => mock_lookup(id)}

    assert manifest |> Manifest.perform() |> Manifest.digest() ==
             {:ok, %{cache_read: mock_lookup(id)}}

    assert Agent.get(pid, & &1) == %{id => mock_lookup(id)}
  end

  defp mock_lookup(id) do
    %{id: id, content: "Anything"}
  end

  defp build_leafed_branch(key, non_leaf) do
    leaf = Manifest.build_step(:leaf, fn _ -> {:ok, :no_rollback, nil} end)
    Manifest.build_branch(fn previous -> is_nil(previous[key]) end, non_leaf, leaf)
  end
end
