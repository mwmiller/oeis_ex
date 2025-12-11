defmodule Mix.Tasks.Check do
  @moduledoc """
  Runs format, test, and credo checks to ensure code quality and consistency.
  """
  use Mix.Task

  @shortdoc "Runs format, test, and credo checks"

  def run(_) do
    Mix.Task.run("format", ["--check-formatted"])

    # Explicitly set MIX_ENV to "test" for the test task
    System.put_env("MIX_ENV", "test")
    Mix.Task.run("test", ["--raise"])

    # Credo typically runs in the "dev" environment, so set it back
    System.put_env("MIX_ENV", "dev")
    Mix.Task.run("credo", ["--strict"])

    Mix.shell().info("All checks passed!")
  end
end
