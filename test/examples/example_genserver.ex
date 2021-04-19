defmodule Stack do
  use GenServer

  # Callbacks

  @impl true
  def init(stack) do
    {:ok, stack}
  end

  @impl true
  def handle_call(:pop, _from, [head | tail]) do
    {:reply, head, tail}
  end

  @impl true
  def handle_cast({:push, element}, state) do
    {:noreply, [element | state]}
  end
end

defmodule Example do
  def push_multiple_elements(pid, outcome \\ :succeed)

  def push_multiple_elements(pid, :succeed) do
    manifest =
      Manifest.new()
      |> Manifest.add_step(
        :first,
        fn _previous -> push_number(pid, 5) end,
        fn _item -> {:ok, GenServer.call(pid, :pop)} end
      )
      |> Manifest.add_step(
        :second,
        &push_number(pid, &1[:first] + 5),
        fn _item -> {:ok, GenServer.call(pid, :pop)} end
      )
      |> Manifest.perform()

    {manifest, Manifest.digest(manifest)}
  end

  def push_multiple_elements(pid, :fail) do
    manifest =
      Manifest.new()
      |> Manifest.add_step(
        :first,
        fn _previous -> push_number(pid, 5) end,
        fn _item -> {:ok, GenServer.call(pid, :pop)} end
      )
      |> Manifest.add_step(
        :second,
        fn _previous -> {:error, :for_test} end,
        fn _item -> {:ok, Genserver.call(pid, :pop)} end
      )
      |> Manifest.perform()

    {manifest, Manifest.digest(manifest)}
  end

  def rollback_example(pid) do
    {manifest, _} = push_multiple_elements(pid, :fail)
    Manifest.rollback(manifest)
  end

  defp push_number(pid, number) do
    GenServer.cast(pid, {:push, number})
    {:ok, number}
  end
end
