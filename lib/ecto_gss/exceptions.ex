defmodule EctoGSS.NoSpreadsheetPid do
  @moduledoc """
  Raised in case spreadsheet pid can't be started, mostl likely because of Google API error.
  """
  defexception [:message]
end

defmodule EctoGSS.NotSchema do
  @moduledoc """
  Raised then passed instead of model schema.
  """
  defexception [:message]
end
