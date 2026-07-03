defmodule EctoGSS.StubToken do
  @moduledoc """
  Offline test token source, wired via `config :elixir_google_spreadsheets,
  token_generator: {EctoGSS.StubToken, :fetch, []}` in `config/test.exs` so the test
  suite boots keyless (no Goth child, no service-account key file).
  """

  @spec fetch() :: {:ok, String.t()}
  def fetch, do: {:ok, "test-token"}
end
