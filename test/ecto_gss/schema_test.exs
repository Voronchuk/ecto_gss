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
end
