# elixir_google_spreadsheets 1.0.0 specs write_row/append_row/clear_row as bare
# :ok, though they can return {:error, Exception.t()} at runtime — making our
# defensive error branches look unreachable (pattern_match_cov). Fixed upstream
# in 1.0.1; delete this file once mix.lock resolves >= 1.0.1.
[
  {"lib/ecto_gss/repo.ex", :pattern_match_cov}
]
