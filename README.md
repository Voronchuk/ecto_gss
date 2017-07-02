# EctoGss
Elixir library to persist Ecto records and changesets in Google Spreadsheets.

This library is based on [elixir_google_spreadsheets](https://github.com/Voronchuk/elixir_google_spreadsheets) on a transport layer,
which relies on __Google Cloud API v4__ and uses __Google Service Accounts__ to manage it's content.

# Setup
1. Use elixir_google_spreadsheets [setup instructions](https://github.com/Voronchuk/elixir_google_spreadsheets)
to set Google Spreadsheet access.
2. Add `{:ecto_gss, "~> 0.1"}` to __mix.exs__ under `deps` function, add `:elixir_google_spreadsheets` in your application list.
3. Run `mix deps.get && mix deps.compile`.

# OTP 20
Currently (01.07.2017) there is an issue in OTP 20, because `:crypto.mpint/1` was moved to another module and it's used in `:goth` dependency `:json_web_token`, you can use this temporary hack as a resolution, by adding this in your deps: `{:json_web_token, git: "https://github.com/starbuildr/json_web_token_ex.git", override: true}`

# Usage
Configure Ecto schema by a provided sample:

```
defmodule Account do
    use EctoGSS.Schema, {
        :model,
        columns: ["A", "Y"],
        list: "List3",
        spreadsheet: "1h85keViqbRzgTN245gEw5s9roxpaUtT7i-mNXQtT8qQ"
    }
    use Ecto.Schema

    schema "accounts" do
        field :nickname, EctoGSS.Schema.List3.A
        field :email, EctoGSS.Schema.List3.Y
    end
end
```

* `spreadsheet` is an id of Google spreadsheet which is used as storage file;
* `list` is the name of spreadsheet list where values will be stored (tested only with latin and numeric names);
* `columns` are the list of Google spreadsheet columns which are used to map a schema values;

Type for each schema column will be generated automatically, based on a provided config values, in a format like `EctoGSS.Schema.[LIST].[COLUMN]`.

Keep in mind that `:id` is used as a system field to store row index information, if you need secure identifier, it's recommended to add `:uid` column and generate it explicitly, for instance with [elixir-uuid](https://github.com/zyro/elixir-uuid) library.

## Repo
When you schema is properly defined, use `EctoGSS.Repo` to work with the supported operations:

* `EctoGSS.Repo.get(Account, id)`
* `EctoGSS.Repo.all(Account, start_id: 5, end_id: 10)`
* `EctoGSS.Repo.all(Account, rows: [1, 3, 5])`
* `EctoGSS.Repo.insert(changeset)`
* `EctoGSS.Repo.update(changeset)`
* `EctoGSS.Repo.insert_or_update(changeset)`
* `EctoGSS.Repo.delete(record)`

Banged operations are also available, check the hex docs for the full list of a supported operations.

# Restrictions
* It's up to you to honour all Google request quotas.
* __This library is in it's early beta, use on your own risk. Pull requests / reports / feedback are welcome.__
