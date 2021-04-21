defmodule Manifest.Merge do
  @moduledoc """
  Defines a `Record` that contains information on how to merge an inner 
  `t:Manifest.t()` with the outer. The merge function will have access to all the
  `previous` results up to the point where the function is being evaluated.
  """
  import Record, only: [defrecord: 3]

  defrecord(:merge, __MODULE__, merge: &__MODULE__.default_merge/1)

  @type merge :: (map() -> Manifest.t())
  @type t :: record(:merge, merge: merge())

  @doc false
  def default_merge(_previous), do: Manifest.new()
end
