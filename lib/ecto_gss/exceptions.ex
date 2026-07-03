defmodule EctoGSS.NoSpreadsheetPid do
  @moduledoc """
  Raised in case spreadsheet pid can't be started, most likely because of Google API error.
  """
  defexception [:message]
end

defmodule EctoGSS.NotSchema do
  @moduledoc """
  Raised when passed instead of model schema.
  """
  defexception [:message]
end
