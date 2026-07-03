defmodule EctoGSS.RepoStubTest do
  @moduledoc """
  Exercises the full `EctoGSS.Repo` CRUD surface offline and keyless, through the real
  `GSS.Spreadsheet -> Client -> Limiter -> Request -> Finch` pipeline, against a localhost
  `EctoGSS.StubModules.HttpServer` backed by a stateful `EctoGSS.StubModules.FakeSheet`.

  `async: false` because the suite mutates the global
  `:elixir_google_spreadsheets, :api_url` application env. The `Authorization: Bearer
  test-token` header comes from the `EctoGSS.StubToken` stub wired in `config/test.exs`,
  so passing requests prove the whole auth path end to end without a real key.
  """
  use ExUnit.Case, async: false

  import Ecto.Changeset

  alias EctoGSS.Repo
  alias EctoGSS.StubModules.{FakeSheet, HttpServer}

  # A unique {sheet_id, list_name} keeps the GSS.Registry-deduped spreadsheet process
  # isolated from every other test file. Never reuse the real test spreadsheet id here.
  @sheet_id "stub-sheet-repo-crud"
  @list_name "StubList"
  @agent :ecto_gss_repo_stub_fake_sheet

  defmodule StubAccount do
    use EctoGSS.Schema, {
      :model,
      columns: ["A", "Y"], list: "StubList", spreadsheet: "stub-sheet-repo-crud"
    }

    use Ecto.Schema

    import Ecto.Changeset

    schema "stub_accounts" do
      field(:nickname, EctoGSS.Schema.StubList.A)
      field(:email, EctoGSS.Schema.StubList.Y)
    end

    def changeset(account, attrs) do
      account
      |> cast(attrs, [:nickname, :email])
      |> validate_required([:nickname, :email])
    end
  end

  setup_all do
    {:ok, _agent} = FakeSheet.start_link(@agent)

    {port, ref} =
      HttpServer.start(fn conn -> FakeSheet.dispatch(@agent, @sheet_id, @list_name, conn) end)

    previous_api_url = Application.get_env(:elixir_google_spreadsheets, :api_url)

    Application.put_env(
      :elixir_google_spreadsheets,
      :api_url,
      "http://localhost:#{port}/v4/spreadsheets/"
    )

    on_exit(fn ->
      if previous_api_url do
        Application.put_env(:elixir_google_spreadsheets, :api_url, previous_api_url)
      else
        Application.delete_env(:elixir_google_spreadsheets, :api_url)
      end

      HttpServer.stop(ref)
      if Process.whereis(@agent), do: Agent.stop(@agent)
    end)

    :ok
  end

  setup do
    FakeSheet.reset(@agent)
    :ok
  end

  test "insert -> get round-trip returns an equal record with an id" do
    changeset = change(%StubAccount{email: "vor@tat.com"}, %{nickname: "Insert"})

    assert {:ok, record} = Repo.insert(changeset)
    assert record.id == 1
    assert record.nickname == "Insert"
    assert Repo.get(StubAccount, record.id) == record
    # The row physically landed in the backing sheet at the inserted index.
    assert FakeSheet.get_row(@agent, record.id) != nil
  end

  test "all/2 with start_id/end_id reads a contiguous range of inserted rows" do
    {:ok, r1} = Repo.insert(change(%StubAccount{email: "a@x.com"}, %{nickname: "A"}))
    {:ok, r2} = Repo.insert(change(%StubAccount{email: "b@x.com"}, %{nickname: "B"}))
    {:ok, r3} = Repo.insert(change(%StubAccount{email: "c@x.com"}, %{nickname: "C"}))

    assert [r1, r2, r3] == Repo.all(StubAccount, start_id: 1, end_id: 3)
  end

  test "all/2 with an explicit rows: list filters out a missing row" do
    {:ok, r1} = Repo.insert(change(%StubAccount{email: "a@x.com"}, %{nickname: "A"}))
    {:ok, r2} = Repo.insert(change(%StubAccount{email: "b@x.com"}, %{nickname: "B"}))
    # Row 99 was never written, so GSS returns a `{}` valueRange -> nil -> filtered out.
    assert [r1, r2] == Repo.all(StubAccount, rows: [r1.id, 99, r2.id])
  end

  test "update: a changed field is persisted and read back" do
    {:ok, record} = Repo.insert(change(%StubAccount{email: "vor@tat.com"}, %{nickname: "Before"}))

    {:ok, updated} = Repo.update(change(record, %{email: "after@tat.com"}))

    assert updated.email == "after@tat.com"
    assert Repo.get(StubAccount, record.id).email == "after@tat.com"
  end

  test "delete: subsequent get returns nil and the row is gone from state" do
    {:ok, record} = Repo.insert(change(%StubAccount{email: "vor@tat.com"}, %{nickname: "Delete"}))
    assert Repo.get(StubAccount, record.id)

    assert {:ok, _} = Repo.delete(record)

    assert Repo.get(StubAccount, record.id) == nil
    assert FakeSheet.get_row(@agent, record.id) == nil
  end

  test "insert_or_update/1 takes the insert branch for a built record and update for a persisted one" do
    # EctoGSS.Repo distinguishes by the changeset's `data.id`: a freshly built struct has
    # id == nil (insert path); a record returned from a prior insert carries an id (update path).
    built = change(%StubAccount{email: "n@x.com"}, %{nickname: "New"})
    assert {:ok, inserted} = Repo.insert_or_update(built)
    assert inserted.id == 1
    assert Repo.get(StubAccount, inserted.id) == inserted

    persisted = change(inserted, %{nickname: "Upserted"})
    assert {:ok, upserted} = Repo.insert_or_update(persisted)
    assert upserted.id == inserted.id
    assert upserted.nickname == "Upserted"
    assert Repo.get(StubAccount, inserted.id).nickname == "Upserted"
  end

  test "get!/2 raises Ecto.NoResultsError for a missing row and for a nil id" do
    assert_raise Ecto.NoResultsError, fn -> Repo.get!(StubAccount, 999) end
    assert_raise Ecto.NoResultsError, fn -> Repo.get!(StubAccount, nil) end
  end

  test "an invalid changeset returns {:error, changeset} without touching the sheet" do
    invalid_insert = StubAccount.changeset(%StubAccount{}, %{email: "no-nickname@x.com"})
    refute invalid_insert.valid?
    assert {:error, %Ecto.Changeset{valid?: false}} = Repo.insert(invalid_insert)
    assert FakeSheet.rows(@agent) == %{}

    {:ok, record} = Repo.insert(change(%StubAccount{email: "vor@tat.com"}, %{nickname: "Keep"}))
    before = FakeSheet.rows(@agent)
    invalid_update = StubAccount.changeset(record, %{nickname: ""})
    refute invalid_update.valid?
    assert {:error, %Ecto.Changeset{valid?: false}} = Repo.update(invalid_update)
    # No write happened: state is untouched by the rejected update.
    assert FakeSheet.rows(@agent) == before
  end

  test ~s(all/2 skips a "!!" comment row) do
    # Column A == "!!" marks a comment row that EctoGSS.Repo filters out.
    comment_row = ["!!"] ++ List.duplicate("", 23) ++ ["ignored@x.com"]
    normal_row = ["Alice"] ++ List.duplicate("", 23) ++ ["alice@x.com"]
    FakeSheet.put_row(@agent, 1, comment_row)
    FakeSheet.put_row(@agent, 2, normal_row)

    assert [%StubAccount{id: 2, nickname: "Alice", email: "alice@x.com"}] =
             Repo.all(StubAccount, start_id: 1, end_id: 2)
  end
end
