defmodule EctoGSS.Repo do
    @moduledoc """
    Repository to use Google Spreadsheets as persistence layer for objects.
    """

    use GenServer
    import Ecto.Changeset
    require Logger;

    @typedoc """
    """
    @type state :: map()

    @type ecto_object :: Ecto.Changeset.t | Ecto.Schema.t
    @type result :: {:ok, Ecto.Schema.t} | {:error, Ecto.Changeset.t}


    @columns [
        "A", "B", "C", "D", "E", "F", "G", "H", "I",
        "J", "K", "L", "M", "N", "O", "P", "Q", "R",
        "S", "T", "U", "V", "W", "X", "Y", "Z"
    ]


    @spec start_link() :: {:ok, pid}
    def start_link do
        initial_state = %{
        }
        GenServer.start_link(__MODULE__, initial_state, name: __MODULE__)
    end

    @spec init(state) :: {:ok, state}
    def init(state) do
        {:ok, state}
    end


    @doc """
    Get several records:

    * by range of rows: `start_id` and `end_id` options;
    * by exact list of rows: `rows` option.
    """
    @spec all(Ecto.Queryable.t, Keyword.t) :: [Ecto.Schema.t]
    def all(schema, opts \\ []) do
        with {:ok, pid} <- get_spreadsheet_pid(schema),
            index when index > 0 <- last_column_index(schema),
            {response_format, {:ok, data}} <- rows_by_params(pid, index, opts)
        do
            response_values_by_opts(response_format, schema, data, opts)
        else
            :error ->
                raise EctoGSS.NoSpreadsheetPid, message: "no pid"
            :invalid_record ->
                raise EctoGSS.NotSchema, message: "not a schema in first param"
            _ ->
                nil
        end
    end


    @doc """
    Get a record by row id, raise if not found.
    """
    @spec get(Ecto.Queryable.t, integer()) :: Ecto.Schema.t | nil | no_return
    def get(schema, id) do
        with {:ok, pid} <- get_spreadsheet_pid(schema),
            index when index > 0 <- last_column_index(schema),
            {:ok, data} <- GSS.Spreadsheet.read_row(pid, id, column_to: index)
        do
            from_spreadsheet_row_values(schema, data, id)
        else
            :error ->
                raise EctoGSS.NoSpreadsheetPid, message: "no pid"
            :invalid_record ->
                raise EctoGSS.NotSchema, message: "not a schema in first param"
            _ ->
                nil
        end
    end

    @doc """
    Get a record by row, raise if not found.
    """
    @spec get!(Ecto.Queryable.t, integer()) :: Ecto.Schema.t | no_return
    def get!(_schema, nil), do: raise %Ecto.NoResultsError{message: "no results found"}
    def get!(schema, id) do
        raise_if_no_results(schema, get(schema, id))
    end


    @doc """
    Add a new record.
    """
    @spec insert(ecto_object) :: result
    def insert(%Ecto.Changeset{data: _data, valid?: true} = changeset) do
        with {:ok, pid} <- get_spreadsheet_pid(changeset),
            object = apply_changes(changeset),
            row_values = spreadsheet_row_values(object),
            id = get_inc_row(pid),
            :ok <- GSS.Spreadsheet.append_row(pid, id, row_values)
        do
            {:ok, Map.put(object, :id, id)}
        else
            :error ->
                {:error, add_error(changeset, :id, "GSS connection error!")}
            :invalid_record ->
                {:error, add_error(changeset, :id, "Invalid input record!")}
            _ ->
                {:error, add_error(changeset, :id, "GSS insert error!")}
        end
    end
    def insert(%Ecto.Changeset{} = changeset), do: {:error, changeset}
    def insert(%{__struct__: _model} = object) do
        object
        |> change(%{})
        |> insert
    end

    @doc """
    Add a new record, raise in case of error.
    """
    @spec insert!(ecto_object) :: Ecto.Schema.t | no_return
    def insert!(changeset) do
        raise_if_changeset_errors insert(changeset), "insert"
    end


    @doc """
    Update an existing record with a row id.
    """
    @spec update(ecto_object) :: {:ok, Ecto.Schema.t} | {:error, Ecto.Changeset.t}
    def update(%Ecto.Changeset{data: %{id: id}, valid?: true} = changeset) do
        with {:ok, pid} <- get_spreadsheet_pid(changeset),
            object = apply_changes(changeset),
            row_values = spreadsheet_row_values(object),
            :ok <- GSS.Spreadsheet.write_row(pid, id, row_values)
        do
            {:ok, Map.put(object, :id, id)}
        else
            :error ->
                {:error, add_error(changeset, :id, "GSS connection error!")}
            :invalid_record ->
                {:error, add_error(changeset, :id, "Invalid input record!")}
            _ ->
                {:error, add_error(changeset, :id, "GSS update error!")}
        end
    end
    def update(%Ecto.Changeset{} = changeset), do: {:error, changeset}

    @doc """
    Update an existing record, raise in case of error.
    """
    @spec update!(Ecto.Changeset.t) :: Ecto.Schema.t | no_return
    def update!(%Ecto.Changeset{} = changeset) do
        raise_if_changeset_errors update(changeset), "update"
    end


    @doc """
    Update an existing record, or insert a new one.
    """
    @spec insert_or_update(Ecto.Changeset.t) :: result
    def insert_or_update(%Ecto.Changeset{valid?: true, data: %{id: record_id}} = changeset)
    when record_id != nil do
        update(changeset)
    end
    def insert_or_update(%Ecto.Changeset{valid?: true} = changeset) do
        insert(changeset)
    end
    def insert_or_update(%Ecto.Changeset{valid?: false} = changeset) do
        {:error, changeset}
    end

    @doc """
    Update an existing record, or insert a new one, raise in case of error.
    """
    @spec insert_or_update!(Ecto.Changeset.t) :: Ecto.Schema.t | no_return
    def insert_or_update!(changeset) do
        raise_if_changeset_errors insert_or_update(changeset), "upsert"
    end


    @doc """
    Delete an existing record.
    """
    @spec delete(ecto_object) :: result
    def delete(%Ecto.Changeset{data: data}) do
        delete(data)
    end
    def delete(%{__struct__: schema, id: id} = record) do
        with {:ok, pid} <- get_spreadsheet_pid(schema),
            :ok <- GSS.Spreadsheet.clear_row(pid, id)
        do
            {:ok, record}
        else
            :error ->
                {:error, add_error(change(record, %{}), :id, "GSS connection error!")}
            :invalid_record ->
                {:error, add_error(change(record, %{}), :id, "Invalid input record!")}
            _ ->
                {:error, add_error(change(record, %{}), :id, "GSS delete error!")}
        end
    end

    @doc """
    Delete an existing record, raise in case of error.
    """
    @spec delete!(ecto_object) :: result | no_return
    def delete!(record) do
        raise_if_changeset_errors delete(record), "delete"
    end


    @spec response_values_by_opts(:rows | :range, module(), [map()], Keyword.t) :: [Ecto.Schema.t]
    defp response_values_by_opts(:rows, schema, data, opts) do
        data
        |> Enum.zip(Keyword.fetch!(opts, :rows))
        |> Enum.map(&(from_spreadsheet_rows(schema, &1)))
        |> Enum.filter(&(&1 != nil))
    end
    defp response_values_by_opts(:range, schema, data, opts) do
        data
        |> Enum.with_index(Keyword.get(opts, :start_id, 1))
        |> Enum.map(&(from_spreadsheet_rows(schema, &1)))
        |> Enum.filter(&(&1 != nil))
    end

    @spec from_spreadsheet_rows(module(), {map(), integer()}) :: Ecto.Schema.t | nil
    defp from_spreadsheet_rows(schema, {row, id}) do
        if row != nil do
            from_spreadsheet_row_values(schema, row, id)
        else
            nil
        end
    end

    @spec from_spreadsheet_row_values(module(), [String.t], String.t) :: Ecto.Schema.t | nil
    defp from_spreadsheet_row_values(schema, [head | _] = values, id) do
        if Enum.join(values) == "" or head == "!!" do
            nil
        else
            @columns
            |> Enum.zip(values)
            |> Enum.into(%{})
            |> to_ecto_record(schema, id)
        end
    end

    @spec to_ecto_record(map(), module(), integer()) :: Ecto.Schema.t
    defp to_ecto_record(letter_map_values, schema, id) do
        instruction = get_schema_fields_types(schema)
        Enum.reduce instruction, struct(schema), fn({key, maybe_column_type}, record) ->
            cond do
                key == :id ->
                    Map.put(record, key, id)
                is_gss_schema_type_module?(maybe_column_type) ->
                    value = Map.get(letter_map_values, maybe_column_type.column())
                    Map.put(record, key, value)
                true ->
                    record
            end
        end
    end


    @spec spreadsheet_row_values(map()) :: [String.t]
    defp spreadsheet_row_values(record) do
        record
        |> letter_map_values
        |> values_with_padding
        # Drop padding in the end
        |> Enum.reverse
        |> Enum.drop_while(fn(x) -> x == "" end)
        |> Enum.reverse
    end

    @spec letter_map_values(Ecto.Schema.t) :: map()
    defp letter_map_values(%{__struct__: model} = record) do
        instruction = get_schema_fields_types(model)
        Enum.reduce instruction, %{}, fn({key, maybe_column_type}, acc) ->
            cond do
                is_gss_schema_type_module?(maybe_column_type) ->
                    Map.put(acc, maybe_column_type.column(), Map.get(record, key))
                true ->
                    acc
            end
        end
    end

    @spec values_with_padding(map()) :: [String.t]
    defp values_with_padding(letter_map_values) do
        Enum.reduce @columns, [], fn(letter, acc) ->
            if Map.has_key?(letter_map_values, letter) do
                acc ++ [Map.get(letter_map_values, letter)]
            else
                acc ++ [""]
            end
        end
    end


    @spec last_column_index(module()) :: integer()
    defp last_column_index(model) do
        instruction = get_schema_fields_types(model)
        index = Enum.reduce instruction, 0, fn({_key, maybe_column_type}, old_index) ->
            cond do
                is_gss_schema_type_module?(maybe_column_type) ->
                    column_letter = maybe_column_type.column()
                    current_index = Enum.find_index @columns, fn(letter) ->
                        letter == column_letter
                    end

                    if current_index != nil and current_index > old_index do
                        current_index
                    else
                        old_index
                    end
                true ->
                    old_index
            end
        end
        index + 1
    end


    @spec get_spreadsheet_pid(Ecto.Changeset.t) :: {:ok, pid()} | :error | :invalid_record
    defp get_spreadsheet_pid(%Ecto.Changeset{} = record) do
        get_spreadsheet_pid(spreadsheet(record), list(record))
    end
    defp get_spreadsheet_pid(schema) do
        if is_gss_schema_module?(schema) do
            get_spreadsheet_pid(schema.spreadsheet(), schema.list())
        else
            :invalid_record
        end
    end
    defp get_spreadsheet_pid(sheet_id, list_name) when is_bitstring(sheet_id) and is_bitstring(list_name) do
        with nil <- GSS.Registry.spreadsheet_pid(sheet_id, list_name: list_name),
            {:ok, pid} <- GSS.Spreadsheet.Supervisor.spreadsheet(sheet_id, list_name: list_name)
        do
            {:ok, pid}
        else
            pid when is_pid(pid) ->
                {:ok, pid}
            _ ->
                :error
        end
    end


    @spec get_inc_row(pid()) :: integer()
    defp get_inc_row(pid) do
        case GSS.Spreadsheet.rows(pid) do
            {:ok, rows} ->
                rows + 1
            _ ->
                1
        end
    end


    @spec spreadsheet(Ecto.Changeset.t) :: String.t
    defp spreadsheet(%Ecto.Changeset{data: data}) do
        data.__struct__.spreadsheet()
    end

    @spec list(Ecto.Changeset.t) :: String.t
    defp list(%Ecto.Changeset{data: data}) do
        data.__struct__.list()
    end


    @spec is_gss_schema_module?(module()) :: boolean()
    defp is_gss_schema_module?(schema) do
        Code.ensure_loaded?(schema) and {:gss_schema, 0} in schema.module_info(:exports)
    end

    @spec is_gss_schema_type_module?(module()) :: boolean()
    defp is_gss_schema_type_module?(gss_schema_type) do
        Code.ensure_loaded?(gss_schema_type) and {:gss_schema_type, 0} in gss_schema_type.module_info(:exports)
    end


    @spec rows_by_params(pid(), integer(), Keyword.t) :: {:rows, {:ok, [map()]}} | {:range, {:ok, [map()]}}
    defp rows_by_params(pid, index, opts) do
        rows = Keyword.get(opts, :rows)
        start_id = Keyword.get(opts, :start_id, 1)
        end_id = Keyword.get(opts, :end_id, 100)

        cond do
            rows != nil ->
                {:rows, GSS.Spreadsheet.read_rows(pid, rows, column_to: index)}
            true ->
                {:range, GSS.Spreadsheet.read_rows(pid, start_id, end_id, column_to: index)}
        end
    end


    # Raise Ecto.NoResultsError if there is no results
    @spec raise_if_no_results(module(), Ecto.Schema.t) :: Ecto.Schema.t | no_return
    defp raise_if_no_results(schema, result) do
        case result do
            nil -> raise Ecto.NoResultsError.exception([queryable: schema])
            record -> record
        end
    end

    # Convert changeset errors, by raising Ecto.InvalidChangesetError
    # Useful for bang (!) functions
    @spec raise_if_changeset_errors(result, String.t) :: Ecto.Schema.t | no_return
    defp raise_if_changeset_errors(result, action) do
        case result do
            {:ok, record} ->
                record
            {:error, changeset} ->
                Logger.error fn ->
                    "GSS #{action} Error: " <> inspect changeset_errors_to_string(changeset)
                end
                raise Ecto.InvalidChangesetError, [action: action, changeset: changeset]
            _ ->
                raise Ecto.InvalidChangesetError, action: action
        end
    end

    # Convert all changeset errors into a single string value.
    @spec changeset_errors_to_string(Ecto.Changeset.t) :: String.t
    defp changeset_errors_to_string(changeset) do
        Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
            Enum.reduce(opts, msg, fn {key, value}, _acc ->
                String.replace(msg, "%{#{key}}", to_string(value))
            end)
        end)
    end

    # Get types for all schema fields
    @spec get_schema_fields_types(module()) :: [{atom(), atom()}]
    defp get_schema_fields_types(schema) do
        Enum.map(schema.__schema__(:fields), fn field ->
            {field, schema.__schema__(:type, field)}
        end)
    end
end
