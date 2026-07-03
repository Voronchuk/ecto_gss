defmodule EctoGSS.Schema do
  @moduledoc """
  Injects the plumbing that lets an `Ecto.Schema` be backed by a Google
  Spreadsheet list (tab).

  ## Usage

      defmodule MyApp.Account do
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

  `use EctoGSS.Schema, {:model, opts}` generates, at compile time:

    * one `Ecto.Type` module per entry in `columns:`, named
      `EctoGSS.Schema.<ListNameWithoutSpaces>.<Column>` (spaces in `list:` are
      stripped to build the module name, e.g. list `"All Accounts"` and column
      `"A"` produce `EctoGSS.Schema.AllAccounts.A`). Each generated type module
      knows the spreadsheet column letter it maps to and is meant to be used as
      the type of a field in the host schema's own `schema/2` block;
    * `spreadsheet/0`, `list/0` and `gss_schema/0` functions injected into the
      host schema module, used by `EctoGSS.Repo` to locate the backing sheet
      and mark the module as a GSS-backed schema.

  ## Locating the spreadsheet

  There are two ways to tell `EctoGSS.Repo` which spreadsheet and list to use:

    * pass `spreadsheet:` (and `list:`) explicitly in `opts`, as shown above; or
    * omit `spreadsheet:` and instead rely on the host schema's
      `@schema_prefix` to supply the spreadsheet id. (This fallback path is
      being repaired in a later task; this moduledoc documents the option
      surface only, not the current runtime behavior of that fallback.)

  ## Compile-time vs. runtime option

  `list:` and `columns:` must be compile-time literals: they are used to name
  the generated `Ecto.Type` modules while this macro is expanding, so their
  values must be known then. `spreadsheet:`, on the other hand, is only
  unquoted into the generated `spreadsheet/0` function body and may be any
  expression valid in the host module (e.g. a module attribute or a call).
  """

  def model(opts) do
    spreadsheet = Keyword.get(opts, :spreadsheet)
    list = Keyword.get(opts, :list)

    for gss_column <- Keyword.get(opts, :columns, []) do
      code =
        quote do
          @behaviour Ecto.Type
          def type, do: :string

          def embed_as(_format), do: :self

          def equal?(value1, value1), do: true
          def equal?(_value1, _value2), do: false

          def cast(integer) when is_integer(integer), do: {:ok, to_string(integer)}
          def cast(string) when is_bitstring(string), do: {:ok, string}
          def cast(_), do: :error

          def load(string) when is_bitstring(string), do: {:ok, string}

          def dump(string) when is_bitstring(string), do: {:ok, string}
          def dump(_), do: :error

          def column, do: unquote(gss_column)
          def list, do: unquote(list)
          def gss_schema_type, do: true
        end

      safe_list_name = String.replace(list, " ", "")

      Module.create(
        Module.concat(EctoGSS.Schema, "#{safe_list_name}.#{gss_column}"),
        code,
        Macro.Env.location(__ENV__)
      )
    end

    quote do
      def spreadsheet, do: unquote(spreadsheet)
      def list, do: unquote(list)
      def gss_schema, do: true
    end
  end

  defmacro __using__({which, opts}) when is_atom(which) do
    apply(__MODULE__, which, [opts])
  end
end
