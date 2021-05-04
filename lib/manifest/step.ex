defmodule Manifest.Step do
  @moduledoc """
  Defines a `Record` that contains the necessary information to perform a step.
  The `:work` key defines the primary function to be run during the step. It 
  should do the actual API call, GenServer call, or DB query. The `:rollback` 
  key defines how the operation should be rolled back in the case of errors. 
  It recieves a single arguement used to identify the resource to be reverted. 
  The `:parser` key determines some form of identifier that the rollback 
  function will recieve as it's argument. Can be anything as long as the 
  rollback can use it.
  """
  import Record, only: [defrecord: 3]
  @type operation :: atom()
  @type valid_returns :: {:ok, any()} | {:ok, :no_rollback, any()} | {:error, any()}
  @type work :: (map() -> valid_returns())
  @type parser :: (any() -> {:ok, any()} | {:error, any()})
  @type rollback :: (any(), map() -> {:ok, any()} | {:error, any()})
  @type t ::
          record(:step,
            operation: operation(),
            work: work(),
            parser: parser(),
            rollback: rollback()
          )

  defrecord(:step, __MODULE__,
    operation: nil,
    work: &__MODULE__.default_work/1,
    parser: &__MODULE__.default_parser/1,
    rollback: &__MODULE__.safe_default_rollback/2
  )

  @doc false
  def default_work(_previous), do: {:ok, :no_rollback, %{}}
  @doc false
  def default_parser(identifier), do: {:ok, identifier}
  @doc false
  def safe_default_rollback(_identifier, _previous), do: {:ok, :noop}
end
