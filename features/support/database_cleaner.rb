# DatabaseCleaner refuses remote DATABASE_URLs by default. In Docker the database host is `db`,
# so allow it only when the URL names a *_test database. A dev or production URL still raises.
DatabaseCleaner.allow_remote_database_url = true if ENV["DATABASE_URL"].to_s.match?(%r{/[^/?]+_test(\?|\z)})
