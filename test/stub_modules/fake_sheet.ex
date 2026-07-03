defmodule EctoGSS.StubModules.FakeSheet do
  @moduledoc """
  Stateful in-memory Google Sheet that backs true CRUD round-trips for
  `EctoGSS.RepoStubTest`. State lives in an `Agent` as `%{rows: %{row_index => [cells]}}`.

  `dispatch/4` matches on `conn.method` + `conn.request_path` DIRECTLY with plain string
  matching (never `Plug.Router`, whose path compiler rejects the literal colons in Sheets
  paths like `A1:E1`, `:append` and `:clear` — see `EctoGSS.StubModules.HttpServer`). It
  answers with the Google-Sheets-shaped JSON that the GSS 1.0 client contract requires:

    * `GET /v4/spreadsheets/{id}` (boot metadata) — one sheet whose `title` is the
      backing `list_name`; without it every `GSS.Spreadsheet` process dies at start with
      `{:shutdown, "failed to load sheet id"}`.
    * `GET .../values/{List}!A1:B` (`rows/1`) — `values` length equals the MAX occupied
      row index (not the count), so `next_id = length + 1` stays collision-free after
      deletes. `{}` when empty → GSS yields `{:ok, 0}`.
    * `POST .../values/{range}:append` — `{"updates" => {"updatedRows", "updatedColumns"}}`,
      both > 0; stores the posted row(s) at the index parsed from the range.
    * `GET .../values/{List}!A{n}:{C}{n}` (`read_row`) — `{"values" => [[cells]]}`, or
      `{}` for a missing row (GSS pads to width, `EctoGSS.Repo` maps to nil).
    * `GET .../values:batchGet?...ranges=...` (`read_rows`) — one `valueRanges` entry PER
      requested range, in order; `{}` for a missing single-row range → nil.
    * `PUT .../values/{range}` (`write_row`) — top-level `{"updatedRows", "updatedColumns"}`.
    * `POST .../values/{List}!A{n}:Z{n}:clear` (`clear_row`) — `{"clearedRange" => ...}`;
      deletes the row from state.

  The module stays dumb: no HTTP knowledge beyond reading a `Plug.Conn`, JSON via the
  built-in `JSON` module.
  """

  import Plug.Conn

  # Row span inside a decoded range such as `List!A5:Y5` or `List!A1:Z1:clear`.
  # Column letters are matched but discarded so an A..Y schema (padded to `A{n}:Y{n}`)
  # and the A..Z clear range are both handled without hardcoding letters.
  @range_rx ~r/!(?:[A-Z]+)(\d+):[A-Z]+(\d+)/

  @spec start_link(atom()) :: Agent.on_start()
  def start_link(name) do
    Agent.start_link(fn -> %{rows: %{}} end, name: name)
  end

  @spec reset(Agent.agent()) :: :ok
  def reset(agent), do: Agent.update(agent, fn _ -> %{rows: %{}} end)

  @doc "Seed a row directly (used to pre-populate e.g. `!!` comment rows in tests)."
  @spec put_row(Agent.agent(), pos_integer(), [String.t()]) :: :ok
  def put_row(agent, index, cells) do
    Agent.update(agent, fn state -> put_in(state, [:rows, index], cells) end)
  end

  @doc "Fetch a stored row (or nil); lets tests assert stub state directly."
  @spec get_row(Agent.agent(), pos_integer()) :: [String.t()] | nil
  def get_row(agent, index), do: Agent.get(agent, fn state -> Map.get(state.rows, index) end)

  @doc "Return the whole `row_index => cells` map for state assertions."
  @spec rows(Agent.agent()) :: %{pos_integer() => [String.t()]}
  def rows(agent), do: Agent.get(agent, fn state -> state.rows end)

  @spec dispatch(Agent.agent(), String.t(), String.t(), Plug.Conn.t()) :: Plug.Conn.t()
  def dispatch(agent, _sheet_id, list_name, %Plug.Conn{method: "GET"} = conn) do
    path = conn.request_path

    cond do
      String.ends_with?(path, "values:batchGet") -> batch_get(agent, conn)
      not String.contains?(path, "/values") -> metadata(conn, list_name)
      String.ends_with?(path, "A1:B") -> rows_count(agent, conn)
      true -> read_row(agent, conn)
    end
  end

  def dispatch(agent, _sheet_id, _list_name, %Plug.Conn{method: "POST"} = conn) do
    path = conn.request_path

    cond do
      String.ends_with?(path, ":clear") -> clear(agent, conn)
      String.ends_with?(path, ":append") -> append(agent, conn)
      true -> json(conn, 500, %{"error" => "unhandled POST #{path}"})
    end
  end

  def dispatch(agent, _sheet_id, _list_name, %Plug.Conn{method: "PUT"} = conn) do
    write(agent, conn)
  end

  def dispatch(_agent, _sheet_id, _list_name, conn) do
    json(conn, 500, %{"error" => "unhandled #{conn.method} #{conn.request_path}"})
  end

  # --- boot metadata --------------------------------------------------------
  defp metadata(conn, list_name) do
    json(conn, 200, %{"sheets" => [%{"properties" => %{"title" => list_name, "sheetId" => 0}}]})
  end

  # --- rows/1: `values` length must equal the MAX occupied row index --------
  defp rows_count(agent, conn) do
    rows = rows(agent)

    if map_size(rows) == 0 do
      json(conn, 200, %{})
    else
      max_index = rows |> Map.keys() |> Enum.max()
      json(conn, 200, %{"values" => Enum.map(1..max_index, fn i -> Map.get(rows, i, []) end)})
    end
  end

  # --- read_row/3 -----------------------------------------------------------
  defp read_row(agent, conn) do
    {start_row, _end_row} = parse_range(conn.request_path)

    case get_row(agent, start_row) do
      nil -> json(conn, 200, %{})
      cells -> json(conn, 200, %{"values" => [cells]})
    end
  end

  # --- read_rows/batchGet: one entry per requested range, in order ----------
  defp batch_get(agent, conn) do
    rows = rows(agent)

    value_ranges =
      conn.query_string
      |> ranges_from_query()
      |> Enum.map(&value_range_for(&1, rows))

    json(conn, 200, %{"valueRanges" => value_ranges})
  end

  defp value_range_for(range, rows) do
    {start_row, end_row} = parse_range(range)

    if start_row == end_row do
      # Single-row range: `{}` for a missing row so GSS yields nil for it.
      case Map.get(rows, start_row) do
        nil -> %{}
        cells -> %{"values" => [cells]}
      end
    else
      # Multi-row batched range: keep `[]` placeholders so positional row ids stay aligned
      # (EctoGSS.Repo maps range results by `Enum.with_index(start_id)`).
      %{"values" => Enum.map(start_row..end_row, fn i -> Map.get(rows, i, []) end)}
    end
  end

  # --- append_row -----------------------------------------------------------
  defp append(agent, conn) do
    {start_row, _end_row} = parse_range(conn.request_path)
    values = body_values(conn)
    store_rows(agent, start_row, values)

    json(conn, 200, %{
      "updates" => %{"updatedRows" => length(values), "updatedColumns" => max_width(values)}
    })
  end

  # --- write_row ------------------------------------------------------------
  defp write(agent, conn) do
    {start_row, _end_row} = parse_range(conn.request_path)
    values = body_values(conn)
    store_rows(agent, start_row, values)

    json(conn, 200, %{"updatedRows" => length(values), "updatedColumns" => max_width(values)})
  end

  # --- clear_row ------------------------------------------------------------
  defp clear(agent, conn) do
    {start_row, end_row} = parse_range(conn.request_path)

    Agent.update(agent, fn state ->
      update_in(state.rows, fn rows -> Map.drop(rows, Enum.to_list(start_row..end_row)) end)
    end)

    json(conn, 200, %{"clearedRange" => conn.request_path})
  end

  # --- helpers --------------------------------------------------------------
  defp store_rows(agent, start_row, values) do
    Agent.update(agent, fn state ->
      values
      |> Enum.with_index(start_row)
      |> Enum.reduce(state, fn {row, i}, acc -> put_in(acc, [:rows, i], row) end)
    end)
  end

  defp body_values(conn) do
    conn.private.raw_body |> JSON.decode!() |> Map.fetch!("values")
  end

  defp max_width(values), do: values |> Enum.map(&length/1) |> Enum.max()

  defp parse_range(str) do
    [_full, start_row, end_row] = Regex.run(@range_rx, str)
    {String.to_integer(start_row), String.to_integer(end_row)}
  end

  # Collect every repeated `ranges=` param (Plug.Conn.fetch_query_params keeps only the
  # last). URI.query_decoder both preserves order and percent-decodes `List%21A1%3AY1`.
  defp ranges_from_query(query_string) do
    query_string
    |> URI.query_decoder()
    |> Enum.filter(fn {k, _v} -> k == "ranges" end)
    |> Enum.map(fn {_k, v} -> v end)
  end

  defp json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> resp(status, JSON.encode!(body))
  end
end
