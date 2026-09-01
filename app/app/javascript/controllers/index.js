import { application } from "./application"

import MapController from "./map_controller"
import SearchController from "./search_controller"
import PanelController   from "./panel_controller"
import RegionsController from "./regions_controller"
import ConfirmController from "./confirm_controller"
import HomeController    from "./home_controller"
import RoutingController from "./routing_controller"
import SidePanelController from "./side_panel_controller"
import AutoDismissController from "./auto_dismiss_controller"
import PlacesController from "./places_controller"
import ServiceToggleController from "./service_toggle_controller"
import ServiceLogsController   from "./service_logs_controller"
import BasemapController       from "./basemap_controller"
import ThemeController         from "./theme_controller"
import StaticMapController     from "./static_map_controller"

application.register("map", MapController)
application.register("search", SearchController)
application.register("panel",   PanelController)
application.register("regions", RegionsController)
application.register("confirm", ConfirmController)
application.register("home",       HomeController)
application.register("routing",    RoutingController)
application.register("side-panel",   SidePanelController)
application.register("auto-dismiss", AutoDismissController)
application.register("places",         PlacesController)
application.register("service-toggle", ServiceToggleController)
application.register("service-logs",   ServiceLogsController)
application.register("basemap",        BasemapController)
application.register("theme",          ThemeController)
application.register("static-map",     StaticMapController)
