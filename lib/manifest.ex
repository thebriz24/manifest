defmodule Manifest do
  @moduledoc """
  Provides a structure for ordering operations that need to happen, and how to 
  roll them back if they fail.

  There are examples of usage in `test/example_test.exs`.
  """

  import __MODULE__.{Branch, Merge, Step}
  alias __MODULE__.{Branch, MalformedReturnError, NotAnAtomError, NotAFunctionError, Step}

  defstruct previous: %{}, steps: [], rollbacks: [], halt?: false, errored: nil, reason: nil

  @type t :: %__MODULE__{
          steps: [Step.t()],
          previous: map(),
          rollbacks: [Step.rollback()],
          halt?: boolean(),
          errored: Step.operation(),
          reason: any()
        }

  @doc """
  Initializes a new `t:Manifest.t()`.

  The manifest is not customizable, so no options can be given to this function.
  """
  @spec new :: t()
  def new, do: %__MODULE__{}

  @doc """
  Builds a `t:Manifest.Step.t()` from the given parameters.

  See `Manifest.Step` for more information on what a step consists of.
  """
  @spec build_step(
          atom(),
          __MODULE__.Step.work(),
          __MODULE__.Step.rollback(),
          __MODULE__.Step.parser()
        ) :: Step.t()
  def build_step(
        operation,
        work,
        rollback \\ &Step.safe_default_rollback/2,
        parser \\ &Step.default_parser/1
      )

  def build_step(operation, _work, _rollback, _parser) when not is_atom(operation),
    do: raise(NotAnAtomError, operation)

  def build_step(_operation, work, _rollback, _parser) when not is_function(work),
    do: raise(NotAFunctionError, key: :work, value: work)

  def build_step(_operation, _work, rollback, _parser) when not is_function(rollback),
    do: raise(NotAFunctionError, key: :rollback, value: rollback)

  def build_step(_operation, _work, _rollback, parser) when not is_function(parser),
    do: raise(NotAFunctionError, key: :parser, value: parser)

  def build_step(operation, work, rollback, parser),
    do: step(operation: operation, work: work, parser: parser, rollback: rollback)

  @deprecated "Use Manifest.merge/2 instead"
  @spec build_branch(Branch.conditional(), Step.t(), Step.t()) :: Branch.t()
  def build_branch(conditional, _success, _failure) when not is_function(conditional),
    do: raise(NotAFunctionError, key: :conditional, value: conditional)

  def build_branch(conditional, step() = success, step() = failure),
    do: branch(conditional: conditional, success: success, failure: failure)

  @doc """
  Adds a `Manifest.Step` to the `:steps` key of the manifest. 

  True to Elixir/Erlang practices, it is prepended to the list. The list is 
  reversed the work is actually performed. 
  """

  @spec add_step(t(), Step.t()) :: t()
  def add_step(manifest, step), do: Map.update(manifest, :steps, [step], &[step | &1])

  @doc """
  Combines `build_step/4` and `add_step/2` into one function.

  See `add_step/2` for more information on how the steps are added and 
  `Manifest.Step` for more information on what a step consists of.
  """
  @spec add_step(
          t(),
          atom(),
          __MODULE__.Step.work(),
          __MODULE__.Step.rollback(),
          __MODULE__.Step.parser()
        ) :: t()

  def add_step(
        manifest,
        operation,
        work,
        rollback \\ &Step.safe_default_rollback/2,
        parser \\ &Step.default_parser/1
      ) do
    step = build_step(operation, work, rollback, parser)
    add_step(manifest, step)
  end

  @deprecated "Use Manifest.merge/2 instead"
  @doc """
  Adds either the first step or the second based on the truthy-ness of the 
  given `conditional` function.
  """
  @spec add_branch(t(), Branch.t()) :: t()
  def add_branch(manifest, branch) do
    add_step(manifest, branch)
  end

  def merge(_manifest, merge) when not is_function(merge),
    do: raise(NotAFunctionError, key: :merge, value: merge)

  def merge(manifest, merge), do: add_step(manifest, merge(merge: merge))

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

  TL;DR: There's three paths a step can take:

  1.  It returns {:ok, term} in which case it will add a rollback to the stack.
  2.  It returns {:ok, :no_rollback, term} where no rollback will be added.
  3.  It returns {:error, term} which will halt the Manifest and no further 
  steps will be performed. You can then choose to roll it all back where it 
  will pop the functions off the stack.

  See `digest/1` as it provides an easier way of extracting pertinent 
  information on what happened during this function. 
  """
  @spec perform(t()) :: t()
  def perform(%__MODULE__{steps: steps} = manifest) do
    steps
    |> Enum.reverse()
    |> perform(manifest)
  end

  @doc """
  Reports on the results of `perform/1`.

  Returns an `:ok` tuple with the value of the `:previous` key which contains 
  the results of all the steps if all steps succeeded. Otherwise it returns an 
  `:error` tuple with the `t:Manifest.Step.operation/0`, as it's second element, 
  the results of that step's `t:Manifest.Step.work/0`, and the value of the 
  `:previous` field at the time of failure. (Which, since all other work is 
  halted, means the summary of work done.) It works essentially the same as the 
  return of `Ecto.Repo.transaction/1` when given an `Ecto.Multi`.
  """
  @spec digest(t()) :: {:ok, map()} | {:error, atom(), any(), map()}
  def digest(%__MODULE__{halt?: true, errored: operation, reason: reason, previous: previous}),
    do: {:error, operation, reason, previous}

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
  @spec rollback(t()) :: {:ok, map()} | {:error, atom(), any(), map()}
  def rollback(%__MODULE__{rollbacks: rollbacks}), do: rollback(rollbacks, %{})

  defp perform([], manifest), do: manifest

  defp perform(_, %__MODULE__{halt?: true} = manifest), do: manifest

  defp perform(
         [merge(merge: merge) | rest],
         %__MODULE__{halt?: false, previous: previous} = manifest
       ) do
    steps =
      case merge.(previous) do
        %__MODULE__{steps: steps} ->
          steps
          |> Enum.reverse()
          |> Enum.concat(rest)

        return ->
          raise MalformedReturnError, function: :merge, term: return
      end

    perform(steps, manifest)
  end

  defp perform(
         [branch(conditional: conditional) = branch | rest],
         %__MODULE__{halt?: false, previous: previous} = manifest
       ) do
    next = if conditional.(previous), do: branch(branch, :success), else: branch(branch, :failure)
    perform([next | rest], manifest)
  end

  defp perform(
         [step(operation: operation, work: work) = step | rest],
         %__MODULE__{halt?: false, previous: previous} = manifest
       ) do
    manifest =
      case work.(previous) do
        {:error, reason} ->
          Map.merge(manifest, %{halt?: true, errored: operation, reason: reason})

        {:ok, :no_rollback, return} ->
          put_previous(manifest, operation, return)

        {:ok, return} ->
          handle_return(return, manifest, step)
      end

    perform(rest, manifest)
  rescue
    e in CaseClauseError -> raise MalformedReturnError, function: :work, term: e.term
  end

  defp handle_return(
         return,
         %{previous: previous} = manifest,
         step(operation: operation, parser: parser, rollback: rollback)
       ) do
    case parser.(return) do
      {:ok, identifier} ->
        manifest
        |> stack_rollback(operation, {rollback, identifier, previous})
        |> put_previous(operation, return)

      {:error, reason} ->
        Map.merge(manifest, %{halt?: true, errored: operation, reason: reason})
    end
  rescue
    e in CaseClauseError -> raise MalformedReturnError, function: :parser, term: e.term
  end

  defp put_previous(manifest, operation, return),
    do: Map.update(manifest, :previous, %{operation => return}, &Map.put(&1, operation, return))

  defp stack_rollback(manifest, operation, rollback),
    do:
      Map.update(manifest, :rollbacks, [{operation, rollback}], fn ids ->
        [{operation, rollback} | ids]
      end)

  defp rollback([], acc), do: {:ok, acc}

  defp rollback([{operation, {rollback, identifier, previous}} | rest], acc) do
    case rollback.(identifier, previous) do
      {:error, reason} -> {:error, operation, reason, acc}
      {_, return} -> rollback(rest, Map.put(acc, operation, return))
    end
  rescue
    e in CaseClauseError -> raise MalformedReturnError, function: :rollback, term: e.term
  end
end
