defmodule Manifest do
  @moduledoc """
  Provides a structure for ordering operations that need to happen, and how to 
  roll them back if they fail.

  There are examples of usage in `test/examples`.
  """

  import __MODULE__.Step, only: [step: 1]
  alias __MODULE__.Step

  defstruct previous: %{}, steps: [], rollbacks: [], halt?: false, errored: nil

  @type t :: %__MODULE__{
          steps: [Step.t()],
          previous: map(),
          rollbacks: [Step.rollback()],
          halt?: boolean(),
          errored: Step.operation()
        }

  @doc """
  Initializes a new `t:Manifest.t()`.

  The manifest is not customizable, so no options can be given to this function.
  """
  @spec new :: t()
  def new, do: %__MODULE__{}

  @doc """
  Adds a `Manifest.Step` to the `:steps` key of the manifest. 

  True to Elixir/Erlang practices, it is prepended to the list. The list is 
  reversed the work is actually performed. 

  See `Manifest.Step` for more information on what a step is.
  """
  @spec add_step(t(), atom(), __MODULE__.Step.work(), __MODULE__.Step.rollback()) :: t()
  def add_step(manifest, operation, work, rollback) do
    step = step(operation: operation, work: work, rollback: rollback)
    Map.update(manifest, :steps, [step], &[step | &1])
  end

  @spec add_step(
          t(),
          atom(),
          __MODULE__.Step.work(),
          __MODULE__.Step.rollback(),
          __MODULE__.Step.parser()
        ) :: t()
  def add_step(manifest, operation, work, rollback, parser) do
    step = step(operation: operation, work: work, parser: parser, rollback: rollback)
    Map.update(manifest, :steps, [step], &[step | &1])
  end

  @doc """
  Performs the steps in the order given to the manifest.

  (Each new call of `add_step/1` prepends a `t:Manifest.Step.t/0` to the list,
  then the list is reversed before performing.) If a step's
  `t:Manifest.Step.work/0` succeeds without returning :no_rollback in the tuple,
  the `t:Manifest.Step.parser/0` finds the identifier, and a
  `t:Manifest.Step.rollback/0` is defined the rollback will be added to the
  `:rollbacks` stack. If a step fails, the `:halt?` will activate and no further
  work will be performed. The `:errored` key will be set to the operation that
  triggered the failure. Whether or not the step fails, a key-value pair will
  be added to the `:previous` field. The `t:Manifest.Step.operation/0` will be
  the key of that key-value pair.

  See `digest/1` as it provides an easier way of extracting pertinent 
  information on what happened during this function. 
  """
  @spec perform(t()) :: t()
  def perform(%__MODULE__{steps: steps} = manifest), do: perform(Enum.reverse(steps), manifest)

  defp perform([], manifest), do: manifest

  defp perform(_, %__MODULE__{halt?: true} = manifest), do: manifest

  defp perform(
         [step(work: work) = step | rest],
         %__MODULE__{halt?: false, previous: previous} = manifest
       ) do
    manifest =
      previous
      |> work.()
      |> handle_results(manifest, step)

    perform(rest, manifest)
  end

  @doc """
  Reports on the results of `perform/1`.

  Returns an `:ok` tuple will the value of the `:previous` key which contains 
  the results of all the steps if all steps succeeded. Otherwise it returns an 
  `:error` tuple with the `t:Manifest.Step.operation/0`, as it's second element, 
  the results of that step's `t:Manifest.Step.work/0`, and the value of the 
  `:previous` field at the time of failure. (Which, since all other work is 
  halted, means the summary of work done.) It works essentially the same as the 
  return of `Ecto.Repo.transaction/1` when given an `Ecto.Multi`.
  """
  @spec digest(t()) :: {:ok, map()} | {:error, atom(), any(), map()}
  def digest(%__MODULE__{halt?: true, errored: operation, previous: previous}),
    do: {:error, operation, Map.get(previous, operation), previous}

  def digest(%__MODULE__{halt?: false, previous: previous}), do: {:ok, previous}

  @doc """
  Check if any of the steps had an error.
  """
  @spec errored?(t()) :: boolean()
  def errored?(%__MODULE__{errored: errored}), do: not is_nil(errored)

  @doc """
  Rolls back each operation in case of failure.

  Each `t:Manifest.Step.t/0` that ran previous to the point of failure, defines 
  a `t:Manifest.Step.rollback/0` in the manifest, and didn't receive a `:no_rollback`
  in tuple that the step's `t:Manifest.Step.work/0` returned, will be rolled back
  in reverse from the order the steps were performed. If any of the rollbacks fail,
  it stops attempting to roll back and returns an `:error` tuple. The error
  tuple has the `t:Manifest.Step.operation/0` where it failed as it's second
  element, the reason as the third, and a map containing the results of all the
  successful roll backs up to that point.

  You can also call `rollback/1` on a completely successful Manifest.
  """
  @spec rollback(t()) :: {:ok, map()} | {:error, {atom(), any()}, map()}
  def rollback(%__MODULE__{rollbacks: rollbacks}), do: rollback(rollbacks, %{})

  defp handle_results({:error, error}, manifest, step(operation: operation)) do
    manifest
    |> put_previous(operation, error)
    |> Map.merge(%{halt?: true, errored: operation})
  end

  defp handle_results({:ok, :no_rollback, return}, manifest, step(operation: operation)),
    do: put_previous(manifest, operation, return)

  defp handle_results({:ok, return}, manifest, step(operation: operation, parser: parser, rollback: rollback)) do
    manifest =
      case parser.(return) do
        {:ok, identifier} -> stack_rollback(manifest, operation, {rollback, identifier})
        {:error, _reason} -> Map.merge(manifest, %{halt?: true, errored: operation})
      end

    put_previous(manifest, operation, return)
  end

  defp put_previous(manifest, operation, return),
    do: Map.update(manifest, :previous, %{operation => return}, &Map.put(&1, operation, return))

  defp stack_rollback(manifest, operation, rollback),
    do:
      Map.update(manifest, :rollbacks, [{operation, rollback}], fn ids ->
        [{operation, rollback} | ids]
      end)

  defp rollback([], acc), do: {:ok, acc}

  defp rollback([{operation, {rollback, identifier}} | rest], acc) do
    case rollback.(identifier) do
      {:error, reason} -> {:error, operation, reason, acc}
      {_, return} -> rollback(rest, Map.put(acc, operation, return))
    end
  end
end
