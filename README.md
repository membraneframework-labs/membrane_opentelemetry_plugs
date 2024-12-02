# Membrane Opentelemetry Plugs

[![Hex.pm](https://img.shields.io/hexpm/v/membrane_opentelemetry_plugs.svg)](https://hex.pm/packages/membrane_opentelemetry_plugs)
[![API Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_opentelemetry_plugs)
[![CircleCI](https://circleci.com/gh/membraneframework/membrane_opentelemetry_plugs.svg?style=svg)](https://circleci.com/gh/membraneframework/membrane_opentelemetry_plugs)

This repository contains plugs that generate opentelemetry spans.

It's a part of the [Membrane Framework](https://membrane.stream).

## Installation

The package can be installed by adding `membrane_opentelemetry_plugs` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:membrane_opentelemetry_plugs, "~> 0.1.0"}
  ]
end
```

## Usage

To enable a plug, you have to include it in the project config. You can also specify, which Membrane pipelines you want to track (defaults to `:all`).

```elixir
config :membrane_opentelemetry_plugs,
  plugs: [Membrane.OpenTelemetry.Plugs.Launch],
  tracked_pipelines: [My.Pipeline, My.Another.Pipeline]
```

Currently the only one plug that exists in this repo is `Membrane.OpenTelemetry.Plugs.Launch`.

## Copyright and License

Copyright 2020, [Software Mansion](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane_template_plugin)

[![Software Mansion](https://logo.swmansion.com/logo?color=white&variant=desktop&width=200&tag=membrane-github)](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane_template_plugin)

Licensed under the [Apache License, Version 2.0](LICENSE)
