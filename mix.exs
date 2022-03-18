defmodule TicketsEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :tickets_ex,
      version: "0.1.0",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:lager, :logger],
      mod: {TicketsEx.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:broadway, "~> 0.6"},
      {:broadway_rabbitmq, "~> 0.6"},
      {:amqp, "~> 1.6"}
    ]
  end
end
