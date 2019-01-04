defmodule EctoGSS.Schema do
  def model(opts) do
    spreadsheet = Keyword.fetch!(opts, :spreadsheet)
    list = Keyword.fetch!(opts, :list)

    for gss_column <- Keyword.get(opts, :columns, []) do
      code =
        quote do
          @behaviour Ecto.Type
          def type, do: :string

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

      Module.create(
        Module.concat(EctoGSS.Schema, "#{list}.#{gss_column}"),
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
