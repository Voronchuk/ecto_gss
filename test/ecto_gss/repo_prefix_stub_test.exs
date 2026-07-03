defmodule EctoGSS.RepoPrefixStubTest do
  @moduledoc """
  Regression coverage for the `@schema_prefix` spreadsheet-id fallback in `EctoGSS.Repo`.

  Exercises both call paths that resolve a schema module's spreadsheet id when
  `spreadsheet:` is omitted from `use EctoGSS.Schema`:

    * the changeset path (`insert/1`, `update/1`), which reaches
      `resolve_spreadsheet/1` / `resolve_list/1` through `spreadsheet/1` and `list/1`;
    * the atom path (`get/2`, `all/2`), via `get_spreadsheet_pid/1`.

  Also covers the "no `spreadsheet:`, no `@schema_prefix`" case, where the existing
  error contracts must still hold: `get`/`all` raise `EctoGSS.NoSpreadsheetPid`, and
  `insert` returns `{:error, changeset}` with the existing "GSS connection error!"
  message.

  `async: false` for the same reason as `EctoGSS.RepoStubTest`: the suite mutates the
  global `:elixir_google_spreadsheets, :api_url` application env. Uses a DIFFERENT
  sheet id / list name than that module so `GSS.Registry`-deduped processes never
  collide.
  """
  use ExUnit.Case, async: false

  import Ecto.Changeset

  alias EctoGSS.Repo
  alias EctoGSS.StubModules.{FakeSheet, HttpServer}

  @sheet_id "stub-sheet-repo-prefix"
  @list_name "PrefixList"
  @agent :ecto_gss_repo_prefix_stub_fake_sheet

  # Schema exercising the @schema_prefix fallback: `list:` given, `spreadsheet:` omitted,
  # sheet id supplied only via @schema_prefix.
  defmodule PrefixAccount do
    use EctoGSS.Schema, {
      :model,
      columns: ["A", "Y"], list: "PrefixList"
    }

    use Ecto.Schema

    import Ecto.Changeset

    @schema_prefix "stub-sheet-repo-prefix"
    schema "prefix_accounts" do
      field(:nickname, EctoGSS.Schema.PrefixList.A)
      field(:email, EctoGSS.Schema.PrefixList.Y)
    end

    def changeset(account, attrs) do
      account
      |> cast(attrs, [:nickname, :email])
      |> validate_required([:nickname, :email])
    end
  end

  # Schema with neither `spreadsheet:` nor `@schema_prefix`: the resolution must still
  # fail per the existing error contracts, not crash.
  defmodule NoPrefixAccount do
    use EctoGSS.Schema, {
      :model,
      columns: ["A", "Y"], list: "NoPrefixList"
    }

    use Ecto.Schema

    import Ecto.Changeset

    schema "no_prefix_accounts" do
      field(:nickname, EctoGSS.Schema.NoPrefixList.A)
      field(:email, EctoGSS.Schema.NoPrefixList.Y)
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

  test "changeset path: insert then update succeed via the @schema_prefix fallback" do
    changeset = change(%PrefixAccount{email: "vor@tat.com"}, %{nickname: "Insert"})

    assert {:ok, record} = Repo.insert(changeset)
    assert record.id == 1
    assert record.nickname == "Insert"

    assert {:ok, updated} = Repo.update(change(record, %{email: "after@tat.com"}))
    assert updated.email == "after@tat.com"
    assert FakeSheet.get_row(@agent, record.id) != nil
  end

  test "atom path: get/2 and all/2 resolve the spreadsheet via the @schema_prefix fallback" do
    {:ok, record} = Repo.insert(change(%PrefixAccount{email: "a@x.com"}, %{nickname: "A"}))

    assert Repo.get(PrefixAccount, record.id) == record
    assert Repo.all(PrefixAccount, start_id: 1, end_id: 1) == [record]
  end

  test "missing spreadsheet and missing @schema_prefix: get/all raise, insert errors cleanly" do
    assert_raise EctoGSS.NoSpreadsheetPid, fn -> Repo.get(NoPrefixAccount, 1) end

    assert_raise EctoGSS.NoSpreadsheetPid, fn ->
      Repo.all(NoPrefixAccount, start_id: 1, end_id: 1)
    end

    changeset = change(%NoPrefixAccount{email: "a@x.com"}, %{nickname: "A"})
    assert {:error, failed} = Repo.insert(changeset)
    assert {:id, {"GSS connection error!", []}} in failed.errors
  end
end
