%{
  configs: [
    %{
      name: "default",
      #
      # Only deviations from Credo's defaults are listed here. Everything not
      # mentioned runs with its stock configuration, so this file stays small
      # and a Credo upgrade brings new checks with it.
      #
      checks: %{
        extra: [
          #
          # Design.AliasUsage flags every fully-qualified nested call. On its
          # stock settings that is 51 findings here, and almost none of them
          # are worth acting on, so it was drowning out the rest of the suite.
          # Two adjustments make it useful again:
          #
          #   * `if_called_more_often_than: 2` — an alias earns its place once
          #     a module is referenced three or more times in a file. A one-off
          #     `Atlas.Control.Preflight.run/1` reads better fully qualified,
          #     especially across a `Boundary` line, where the full name is
          #     what tells the reader a boundary is being crossed.
          #
          #   * tests excluded — the bulk of the findings there are
          #     `Plug.Conn.resp/3` inside Bypass stubs and the mix task under
          #     test being named in full. Both are the conventional form; an
          #     alias would make the test less explicit, not more.
          #
          # `if_nested_deeper_than: 2` is Credo's own default, restated because
          # naming a check in `extra` replaces its parameters wholesale rather
          # than merging with them.
          #
          {Credo.Check.Design.AliasUsage,
           [
             if_nested_deeper_than: 2,
             if_called_more_often_than: 2,
             files: %{excluded: ["test/"]}
           ]}
        ]
      }
    }
  ]
}
