ExUnit.start()

# The integration test suite (`test/oeis_integration_test.exs`) is tagged as
# `:external` because it makes real HTTP requests to the OEIS server.
#
# By default, `mix test` runs all tests, including external ones.
# To exclude these external tests, you can run:
#
# mix test --exclude external
