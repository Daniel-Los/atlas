defmodule AtlasWeb.SidePanelTest do
  use AtlasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders mobile tabs in swipe order and exposes the active tab" do
    html =
      render_component(&AtlasWeb.SidePanel.side_panel/1,
        active_tab: "places",
        mobile_panel_open: true,
        search_query: "",
        search_results: [],
        directions: nil,
        mode: "auto",
        places: [],
        tiles_url: "",
        theme: "forest-patina",
        service_status: %{}
      )

    assert html =~ ~s(data-active-tab="places")

    tab_positions =
      Enum.map(~w(search route places settings), fn tab ->
        {position, _length} = :binary.match(html, ~s(phx-value-tab="#{tab}"))
        position
      end)

    assert tab_positions == Enum.sort(tab_positions)
  end
end
