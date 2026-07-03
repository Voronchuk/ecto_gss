defmodule EctoGSS.RepoLiveTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  defmodule Account do
    # EctoGSS.Schema.model/1 only `unquote`s `spreadsheet:` into the generated code, so it
    # can safely come from a module attribute (resolved at Account's own compile time).
    # `list:` and `columns:` are consumed directly by Keyword.get/2 at macro-expansion time
    # (they name the generated modules), so they MUST remain literals.
    @spreadsheet_id Application.compile_env!(:ecto_gss, :spreadsheet_id)

    use EctoGSS.Schema, {
      :model,
      columns: ["A", "Y"], list: "List3", spreadsheet: @spreadsheet_id
    }

    use Ecto.Schema

    schema "accounts" do
      field(:nickname, EctoGSS.Schema.List3.A)
      field(:email, EctoGSS.Schema.List3.Y)
    end
  end

  test "get record from a Repo" do
    changeset = Ecto.Changeset.change(%Account{email: "vor@tat.com"}, %{nickname: "Update"})
    {:ok, record} = EctoGSS.Repo.insert(changeset)
    assert EctoGSS.Repo.get(Account, record.id) == record
  end

  test "get multiple records from a Repo" do
    changeset = Ecto.Changeset.change(%Account{email: "vor@tat.com"}, %{nickname: "All"})
    {:ok, record1} = EctoGSS.Repo.insert(changeset)
    changeset = Ecto.Changeset.change(%Account{email: "vor@tat.com"}, %{nickname: "All"})
    {:ok, record2} = EctoGSS.Repo.insert(changeset)

    assert [record1, record2] ==
             EctoGSS.Repo.all(Account, start_id: record1.id, end_id: record2.id)

    assert [record1, record2] == EctoGSS.Repo.all(Account, rows: [record1.id, record2.id])
  end

  test "insert record in a Repo" do
    changeset = Ecto.Changeset.change(%Account{email: "vor@tat.com"}, %{nickname: "Insert"})
    {:ok, record} = EctoGSS.Repo.insert(changeset)
    assert record.id
  end

  test "update record in a Repo" do
    changeset = Ecto.Changeset.change(%Account{email: "vor@tat.com"}, %{nickname: "Update"})
    {:ok, record} = EctoGSS.Repo.insert(changeset)
    changeset = Ecto.Changeset.change(record, %{email: "updated@tat.com"})
    {:ok, record} = EctoGSS.Repo.update(changeset)
    assert record.email == "updated@tat.com"
  end

  test "delete record in a Repo" do
    changeset = Ecto.Changeset.change(%Account{email: "vor@tat.com"}, %{nickname: "Delete"})
    {:ok, record} = EctoGSS.Repo.insert(changeset)
    assert EctoGSS.Repo.get(Account, record.id)
    {:ok, _} = EctoGSS.Repo.delete(record)
    refute EctoGSS.Repo.get(Account, record.id)
  end
end
