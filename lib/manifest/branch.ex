defmodule Manifest.Branch do
  @moduledoc """
  Defines a `Record` that contains information on how to branch to perform 
  different steps. When the conditional returns a true value then the success 
  step is performed, otherwise the failure step is performed.
  """
  @deprecated
  import Manifest.Step, only: [step: 0]
  import Record, only: [defrecord: 3]

  alias Manifest.Step

  defrecord(:branch, __MODULE__,
    conditional: &__MODULE__.default_conditional/1,
    success: step(),
    failure: step()
  )

  @type conditional :: (map() -> boolean())
  @type t :: record(:branch, conditional: conditional(), success: Step.t(), failure: Step.t())

  @doc false
  def default_conditional(_previous), do: true
end
