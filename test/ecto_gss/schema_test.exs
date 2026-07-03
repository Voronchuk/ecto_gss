defmodule EctoGSS.SchemaTest do
  use ExUnit.Case, async: true

  defmodule Account do
    use EctoGSS.Schema, {
      :model,
      columns: ["A", "Y"],
      list: "All Accounts",
      spreadsheet: "1h85keViqbRzgTN245gEw5s9roxpaUtT7i-mNXQtT8qQ"
    }

    use Ecto.Schema

    schema "accounts" do
      field(:nickname, EctoGSS.Schema.AllAccounts.A)
      field(:email, EctoGSS.Schema.AllAccounts.Y)
    end
  end

  test "list names with spaces" do
    assert match?({:module, _}, Code.ensure_compiled(EctoGSS.Schema.AllAccounts.A))
  end

  test "omitting :list raises a clear ArgumentError instead of crashing in String.replace/3" do
    # A nested `defmodule` written directly in a test body would be compiled eagerly,
    # as part of compiling this file, before ExUnit ever runs the test -- so
    # `assert_raise` could never catch it. Deferring compilation to `Code.eval_string/1`
    # (which runs at test-execution time) lets the raise happen where `assert_raise`
    # can observe it.
    assert_raise ArgumentError, ~r/requires a :list option/, fn ->
      Code.eval_string("""
      defmodule EctoGSS.SchemaTest.MissingList do
        use EctoGSS.Schema, {:model, columns: ["A"]}
      end
      """)
    end
  end
end
