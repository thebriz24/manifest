defmodule Manifest.Test do
  use ExUnit.Case

  alias Manifest.{MalformedReturnError, NotAFunctionError, NotAnAtomError}

  setup do
    [placeholder: fn _ -> {:ok, nil} end]
  end

  describe "build_step/4" do
    test "if :operation isn't an atom", %{placeholder: function} do
      assert_raise NotAnAtomError, fn ->
        Manifest.build_step("Not an atom", function, function)
      end
    end

    test "if :work isn't a function", %{placeholder: function} do
      assert_raise NotAFunctionError, fn ->
        Manifest.build_step(:atom, "Not a function", function)
      end
    end

    test "if :parser isn't a function", %{placeholder: function} do
      assert_raise NotAFunctionError, fn ->
        Manifest.build_step(:atom, function, function, "Not a function")
      end
    end

    test "if :rollback isn't a function", %{placeholder: function} do
      assert_raise NotAFunctionError, fn ->
        Manifest.build_step(:atom, function, "Not a function")
      end
    end

    test "no way to enforce arity of given functions" do
      Manifest.build_step(:atom, fn -> {:error, :not_enough_parameters} end, fn _, _, _ ->
        {:error, :too_many_parameters}
      end)
    end

    test "no way to enforce return values of given functions" do
      Manifest.build_step(:atom, fn _ -> :not_valid_return end, fn _ -> :same end)
    end
  end

  describe "build_branch/3" do
    setup %{placeholder: function} do
      success = Manifest.build_step(:success, function)
      failure = Manifest.build_step(:failure, function)
      [success: success, failure: failure]
    end

    test "if :conditional isn't a function", %{success: success, failure: failure} do
      assert_raise NotAFunctionError, fn ->
        Manifest.build_branch("Not a function", success, failure)
      end
    end

    test "no way to enforce arity of given functions", %{success: success, failure: failure} do
      Manifest.build_branch(fn -> false end, success, failure)
    end

    test "no way to enforce return values of given functions", %{
      success: success,
      failure: failure
    } do
      Manifest.build_branch(fn _ -> {:error, :should_be_bool} end, success, failure)
    end
  end

  describe "add_step/2" do
    test "simply prepends step to steps list", %{placeholder: placeholder} do
      step = Manifest.build_step(:atom, placeholder)
      assert %Manifest{steps: [^step]} = Manifest.add_step(Manifest.new(), step)
    end
  end

  describe "add_branch/2" do
    test "simply prepends branch to steps list", %{placeholder: placeholder} do
      step = Manifest.build_step(:atom, placeholder)
      branch = Manifest.build_branch(fn _ -> true end, step, step)
      assert %Manifest{steps: [^branch]} = Manifest.add_step(Manifest.new(), branch)
    end
  end

  describe "merge/2" do
    test "if :merge isn't a function" do
      assert_raise NotAFunctionError, fn ->
        Manifest.merge(Manifest.new(), "Not a function")
      end
    end

    test "no way to enforce arity of given functions" do
      Manifest.merge(Manifest.new(), fn -> Manifest.new() end)
    end

    test "no way to enforce return values of given functions" do
      Manifest.merge(Manifest.new(), fn _ -> :ok end)
    end

    test "simply prepends branch to steps list" do
      merge = fn _ -> Manifest.new() end
      import Manifest.Merge
      assert %Manifest{steps: [merge(merge: ^merge)]} = Manifest.merge(Manifest.new(), merge)
    end
  end

  describe "perform/1" do
    test "functions with wrong arity will fail during runtime" do
      assert_raise BadArityError, fn ->
        Manifest.new()
        |> Manifest.add_step(:atom, fn -> {:error, :not_enough_parameters} end, fn _, _, _ ->
          {:error, :too_many_parameters}
        end)
        |> Manifest.perform()
      end

      assert_raise BadArityError, fn ->
        Manifest.new()
        |> Manifest.merge(fn -> Manifest.new() end)
        |> Manifest.perform()
      end
    end

    test "functions with malformed returns will fail during runtime" do
      assert_raise MalformedReturnError, fn ->
        Manifest.new()
        |> Manifest.add_step(:atom, fn _ -> :not_valid_return end, fn _ -> :same end)
        |> Manifest.perform()
      end

      assert_raise MalformedReturnError, fn ->
        Manifest.new()
        |> Manifest.merge(fn _ -> :not_valid_return end)
        |> Manifest.perform()
      end
    end

    test "work functions returning an :error tuple will halt steps" do
      results =
        Manifest.new()
        |> Manifest.add_step(:first, fn _previous -> {:ok, nil} end, fn _id -> {:ok, nil} end)
        |> Manifest.add_step(:second, fn _previous -> {:error, :for_fun} end, fn _id ->
          {:ok, nil}
        end)
        |> Manifest.perform()

      assert results.halt?
      assert results.errored == :second
      assert results.previous == %{first: nil}
      assert results.reason == :for_fun
    end

    test "parser functions returning an :error tuple will halt steps" do
      results =
        Manifest.new()
        |> Manifest.add_step(
          :first,
          fn _previous -> {:ok, nil} end,
          fn _id -> {:ok, nil} end,
          fn _id -> {:error, :problem} end
        )
        |> Manifest.add_step(:second, fn _previous -> {:error, nil} end, fn _id -> {:ok, nil} end)
        |> Manifest.perform()

      assert results.halt?
      assert results.errored == :first
      assert results.previous == %{}
      assert results.reason == :problem
    end

    test "work functions returning an :no_rollback tuple will not add rollback to stack" do
      results =
        Manifest.new()
        |> Manifest.add_step(:first, fn _previous -> {:ok, :no_rollback, nil} end, fn _id ->
          {:ok, nil}
        end)
        |> Manifest.perform()

      assert results.previous == %{first: nil}
      assert results.rollbacks == []
    end

    test "work functions returning :ok tuple will add the rollback to the stack" do
      rollback = fn _id -> {:ok, nil} end

      results =
        Manifest.new()
        |> Manifest.add_step(:first, fn _previous -> {:ok, 1} end, rollback)
        |> Manifest.perform()

      assert results.previous == %{first: 1}
      assert results.rollbacks == [first: {rollback, 1}]
    end

    test "parser functions returning :ok tuple will add the rollback to the stack with transformed identifier" do
      rollback = fn _id -> {:ok, nil} end

      results =
        Manifest.new()
        |> Manifest.add_step(:first, fn _previous -> {:ok, 1} end, rollback, fn id ->
          {:ok, id * 2}
        end)
        |> Manifest.perform()

      assert results.previous == %{first: 1}
      assert results.rollbacks == [first: {rollback, 2}]
    end

    test "branch with a true conditional will perform the first step" do
      success =
        Manifest.build_step(:success, fn _previous -> {:ok, nil} end, fn _id -> {:ok, nil} end)

      failure =
        Manifest.build_step(:failure, fn _previous -> {:error, :for_fun} end, fn _id ->
          {:ok, nil}
        end)

      results =
        Manifest.new()
        |> Manifest.add_step(:first, fn _previous -> {:ok, nil} end, fn _id -> {:ok, nil} end)
        |> Manifest.add_branch(
          Manifest.build_branch(fn %{first: result} -> is_nil(result) end, success, failure)
        )
        |> Manifest.perform()

      refute results.halt?
      assert results.previous == %{first: nil, success: nil}
    end

    test "branch with a false conditional will perform the second step" do
      success =
        Manifest.build_step(:success, fn _previous -> {:ok, nil} end, fn _id -> {:ok, nil} end)

      failure =
        Manifest.build_step(:failure, fn _previous -> {:error, :for_fun} end, fn _id ->
          {:ok, nil}
        end)

      results =
        Manifest.new()
        |> Manifest.add_step(:first, fn _previous -> {:ok, nil} end, fn _id -> {:ok, nil} end)
        |> Manifest.add_branch(
          Manifest.build_branch(fn %{first: result} -> not is_nil(result) end, success, failure)
        )
        |> Manifest.perform()

      assert results.halt?
      assert results.errored == :failure
      assert results.previous == %{first: nil}
      assert results.reason == :for_fun
    end
  end

  describe "digest/1" do
    test "returns errored operation along with all previous results" do
      results =
        Manifest.new()
        |> Manifest.add_step(:first, fn _previous -> {:ok, nil} end, fn _id -> {:ok, nil} end)
        |> Manifest.add_step(:second, fn _previous -> {:error, :for_fun} end, fn _id ->
          {:ok, nil}
        end)
        |> Manifest.perform()
        |> Manifest.digest()

      assert results == {:error, :second, :for_fun, %{first: nil}}
    end

    test "returns all results" do
      results =
        Manifest.new()
        |> Manifest.add_step(:first, fn _previous -> {:ok, nil} end, fn _id -> {:ok, nil} end)
        |> Manifest.add_step(:second, fn _previous -> {:ok, nil} end, fn _id -> {:ok, nil} end)
        |> Manifest.perform()
        |> Manifest.digest()

      assert results == {:ok, %{first: nil, second: nil}}
    end
  end

  describe "rollback/1" do
    test "functions with wrong arity will fail during runtime" do
      assert_raise BadArityError, fn ->
        Manifest.new()
        |> Manifest.add_step(:atom, fn _ -> {:ok, :right_number_of_parameters} end, fn _, _, _ ->
          {:error, :too_many_parameters}
        end)
        |> Manifest.perform()
        |> Manifest.rollback()
      end
    end

    test "functions with malformed returns will fail during runtime" do
      assert_raise MalformedReturnError, fn ->
        Manifest.new()
        |> Manifest.add_step(:atom, fn _ -> {:ok, :valid_return} end, fn _ -> :invalid_return end)
        |> Manifest.perform()
        |> Manifest.rollback()
      end
    end

    test "rollback functions returning an :error tuple will simply stop trying to roll back" do
      results =
        Manifest.new()
        |> Manifest.add_step(:first, fn _previous -> {:ok, nil} end, fn _id ->
          {:error, "can't rollback"}
        end)
        |> Manifest.add_step(:second, fn _previous -> {:ok, nil} end, fn _id -> {:ok, nil} end)
        |> Manifest.add_step(:third, fn _previous -> {:error, :for_fun} end, fn _id ->
          {:ok, nil}
        end)
        |> Manifest.perform()
        |> Manifest.rollback()

      assert results == {:error, :first, "can't rollback", %{second: nil}}
    end

    test "returns the results of all rollbacks" do
      results =
        Manifest.new()
        |> Manifest.add_step(:first, fn _previous -> {:ok, nil} end, fn _id -> {:ok, nil} end)
        |> Manifest.add_step(:second, fn _previous -> {:ok, nil} end, fn _id -> {:ok, nil} end)
        |> Manifest.add_step(:third, fn _previous -> {:error, :for_fun} end, fn _id ->
          {:ok, nil}
        end)
        |> Manifest.perform()
        |> Manifest.rollback()

      assert results == {:ok, %{first: nil, second: nil}}
    end
  end
end
