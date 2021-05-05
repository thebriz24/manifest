defmodule Manifest.DuplicateOperationError do
  defexception [:message]
  @impl true
  def exception(value), do: %__MODULE__{message: "Operation (#{value}) already exists."}
end

defmodule Manifest.NotAnAtomError do
  defexception [:message]

  @impl true
  def exception(value),
    do: %__MODULE__{
      message: ":operation must have an atom for it's value, received: #{inspect(value)}"
    }
end

defmodule Manifest.NotAFunctionError do
  defexception [:key, :value]

  @impl true
  def message(%__MODULE__{key: key, value: value}),
    do: "#{inspect(key)} must have a function for it's value, received: #{inspect(value)}"
end

defmodule Manifest.MalformedReturnError do
  defexception [:function, :term]

  @impl true
  def message(%__MODULE__{function: :work, term: term}),
    do: format("three", ", {:ok, :no_rollback, term()},", term)

  def message(%__MODULE__{function: _, term: term}), do: format("two", term)

  defp format(text_number, possible \\ nil, term),
    do:
      "Was expecting one of #{text_number} return values ({:ok, term()}#{possible} or {:error, term()}), but got #{
        inspect(term)
      }"
end
