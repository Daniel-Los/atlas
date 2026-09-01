module Admin
  class BaseController < ApplicationController
    before_action :require_admin_configured
    before_action :authenticate

    rescue_from ControlPlaneClient::Unavailable do |e|
      respond_to do |format|
        format.html { render "admin/errors/sidecar_unavailable", status: :service_unavailable, locals: { message: e.message } }
        format.json { render json: { error: { code: "SIDECAR_UNAVAILABLE", message: e.message } }, status: :service_unavailable }
      end
    end

    rescue_from ControlPlaneClient::BadResponse do |e|
      respond_to do |format|
        format.html { render "admin/errors/sidecar_error", status: :bad_gateway, locals: { message: e.message } }
        format.json { render json: { error: { code: "SIDECAR_ERROR", message: e.message } }, status: :bad_gateway }
      end
    end

    rescue_from RegionCatalog::Region::NotFound do |e|
      respond_to do |format|
        format.html { render "admin/errors/region_not_found", status: :unprocessable_entity, locals: { message: e.message } }
        format.json { render json: { error: { code: "REGION_NOT_FOUND", message: e.message } }, status: :unprocessable_entity }
      end
    end

    private

    def require_admin_configured
      return if ADMIN_CHECK_OK
      render plain:
        "Admin panel unconfigured. Set ADMIN_USERNAME and ADMIN_PASSWORD in .env, then `make restart`.",
        status: :service_unavailable
    end

    def authenticate
      authenticate_or_request_with_http_basic("Dawarich Atlas admin") do |user, pass|
        ActiveSupport::SecurityUtils.secure_compare(user, ENV.fetch("ADMIN_USERNAME", "")) &
        ActiveSupport::SecurityUtils.secure_compare(pass, ENV.fetch("ADMIN_PASSWORD", ""))
      end
    end
  end
end
