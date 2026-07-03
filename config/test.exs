import Config

config :ecto_gss,
  spreadsheet_id:
    System.get_env("GSS_TEST_SPREADSHEET_ID", "1h85keViqbRzgTN245gEw5s9roxpaUtT7i-mNXQtT8qQ")

config :elixir_google_spreadsheets, token_generator: {EctoGSS.StubToken, :fetch, []}

config :logger, level: :info

if File.exists?("config/test.local.exs") do
  import_config "test.local.exs"
end
