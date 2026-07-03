# EctoGSS

Ecto-style objects backed by rows in a Google Spreadsheet, built on top of
[elixir_google_spreadsheets](https://github.com/Voronchuk/elixir_google_spreadsheets), which talks
to the Google Sheets API v4 via a Service Account.

# Setup

> **Upgrading to v1.0:** requires Elixir >= 1.18 and `elixir_google_spreadsheets ~> 1.0`.
> Authentication is now configured through gss's runtime-read keys — see [Authentication
> options](https://github.com/Voronchuk/elixir_google_spreadsheets#authentication-options) below.
> `EctoGSS.Repo` is no longer a GenServer; remove it from your supervision tree if you had it
> there. The unused `EctoGss` module was removed. The `@schema_prefix` style now actually works
> (it previously crashed).

1. Follow [elixir_google_spreadsheets' setup
   steps](https://github.com/Voronchuk/elixir_google_spreadsheets#setup) to create a Google
   Service Account and share your spreadsheet with it.
2. Add `{:ecto_gss, "~> 1.0"}` to `mix.exs` under `deps`. This pulls in `elixir_google_spreadsheets
   ~> 1.0` transitively — dependency applications start automatically, so there's no need to add
   `:elixir_google_spreadsheets` to `extra_applications` anymore.
3. Point `elixir_google_spreadsheets` at your credentials. A bearer token is resolved at request
   time from the first configured source, in order: `token_generator` → `goth` → `source` →
   `json` — see [Authentication
   options](https://github.com/Voronchuk/elixir_google_spreadsheets#authentication-options) for
   the full list. A minimal example using the `json:` path, loaded at runtime so the key isn't
   baked into a release:

    ```elixir
    # config/runtime.exs
    config :elixir_google_spreadsheets,
      json: File.read!(System.fetch_env!("GOOGLE_SERVICE_ACCOUNT_JSON_PATH"))
    ```

4. Run `mix deps.get && mix deps.compile`.

Quota alignment (60 read + 60 write requests/min/user) and automatic retry on `429` are inherited
from `elixir_google_spreadsheets` 1.0 — no `:client` tuning is needed.

# Usage

Pair `use EctoGSS.Schema, {:model, opts}` with `use Ecto.Schema` to back an Ecto schema with a
spreadsheet list (tab). There are two ways to tell `EctoGSS.Repo` which spreadsheet to use.

### Explicit `spreadsheet:`

```elixir
defmodule MyApp.Account do
  use EctoGSS.Schema, {
    :model,
    columns: ["A", "Y"],
    list: "List3",
    spreadsheet: "1h85keViqbRzgTN245gEw5s9roxpaUtT7i-mNXQtT8qQ"
  }

  use Ecto.Schema

  schema "accounts" do
    field(:nickname, EctoGSS.Schema.List3.A)
    field(:email, EctoGSS.Schema.List3.Y)
  end
end
```

### `@schema_prefix`

Omit `spreadsheet:` and supply the spreadsheet id via `@schema_prefix` instead —
`EctoGSS.Repo` falls back to it whenever `spreadsheet/0` returns `nil`:

```elixir
defmodule MyApp.Account do
  use EctoGSS.Schema, {
    :model,
    columns: ["A", "Y"],
    list: "List3"
  }

  use Ecto.Schema

  @schema_prefix "1h85keViqbRzgTN245gEw5s9roxpaUtT7i-mNXQtT8qQ"
  schema "accounts" do
    field(:nickname, EctoGSS.Schema.List3.A)
    field(:email, EctoGSS.Schema.List3.Y)
  end
end
```

> `list:` is always required — it names the generated column type modules
> (`EctoGSS.Schema.<List>.<Column>`) — and, like `columns:`, must be a compile-time literal.
> `spreadsheet:` may be any expression (a module attribute, a function call, etc.), which is why
> it's the one that can be supplied via `@schema_prefix` instead.

`:id` is not a spreadsheet column: it's populated from the row index. Rows whose first column is
`"!!"` are treated as comments and skipped by both `get/2` and `all/2`.

## Repo

Once a schema is defined, `EctoGSS.Repo` provides the usual Ecto-like operations:

* `EctoGSS.Repo.get(Account, id)` / `get!(Account, id)`
* `EctoGSS.Repo.all(Account, start_id: 1, end_id: 100)` — contiguous range of rows
* `EctoGSS.Repo.all(Account, rows: [1, 3, 5])` — exact list of rows
* `EctoGSS.Repo.insert(changeset)` / `insert!(changeset)`
* `EctoGSS.Repo.update(changeset)` / `update!(changeset)`
* `EctoGSS.Repo.insert_or_update(changeset)` / `insert_or_update!(changeset)`
* `EctoGSS.Repo.delete(record)` / `delete!(record)`

# Restrictions

* Columns are limited to `A`-`Z` (26 max) per schema.
* Each schema maps to exactly one worksheet (list/tab).

# Testing

`mix test` runs the whole suite offline and keyless, against a local stub HTTP server.

Tests that hit the real Google Sheets API are tagged `:integration` and excluded by default:

```sh
mix test --include integration
```

This needs a `config/test.local.exs` (gitignored) with real credentials:

```elixir
config :elixir_google_spreadsheets,
  token_generator: nil,
  json: File.read!("./config/service_account.json")
```

Point the suite at your own copy of the test spreadsheet with the `GSS_TEST_SPREADSHEET_ID`
environment variable.
