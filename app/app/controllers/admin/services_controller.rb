module Admin
  class ServicesController < BaseController
    def index
      @services = Service.order(:profile, :name)
      @regions  = RegionCatalog.load_dir(regions_dir).regions.values
      @region_selection = RegionSelection.active_names
      @active_regions   = @region_selection
      render "admin/services/index"
    end

    def update
      service = Service.find_by!(name: params[:name])
      wanted  = ActiveModel::Type::Boolean.new.cast(params[:enabled])
      Service.transaction do
        service.update!(enabled: wanted)
        if wanted
          ControlPlaneClient.default.enable!(service.name)
        else
          ControlPlaneClient.default.disable!(service.name)
        end
      end

      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("service_#{service.name}", partial: "admin/services/service_card", locals: { service: service }) }
        format.html { head :ok }
        format.json { render json: { name: service.name, enabled: service.enabled }, status: :ok }
      end
    rescue ActiveRecord::RecordNotFound
      render plain: "service not found", status: :not_found
    end

    def logs
      tail = (params[:tail] || 200).to_i.clamp(10, 2000)
      body = ControlPlaneClient.default.logs(params[:name], tail: tail)
      render plain: body, content_type: "text/plain"
    rescue ControlPlaneClient::Unavailable => e
      render plain: "Sidecar unreachable: #{e.message}", status: :service_unavailable
    rescue ControlPlaneClient::BadResponse => e
      render plain: e.message, status: :bad_gateway
    end

    def update_now
      service = Service.find_by!(name: params[:name])
      entry   = service.dataset_entry
      return head :unprocessable_entity unless entry
      return head :conflict unless service.begin_update!

      ControlPlaneClient.default.update!(service.name, update_kind: entry.update_kind)
      respond_with_card(service)
    rescue ControlPlaneClient::Unavailable, ControlPlaneClient::BadResponse => e
      service.finish_update!(success: false, error: e.message)
      respond_with_card(service, status: :bad_gateway)
    end

    def toggle_auto
      service = Service.find_by!(name: params[:name])
      wanted  = ActiveModel::Type::Boolean.new.cast(params[:auto_update_enabled])
      attrs   = { auto_update_enabled: wanted }
      # Re-arming clears the kill-switch so the scheduler can pick it up again.
      attrs[:last_update_status] = nil if wanted && service.update_failed?
      service.update!(attrs)
      respond_with_card(service)
    end

    def schedule_update
      service = Service.find_by!(name: params[:name])
      cron    = params[:update_schedule_cron].to_s.strip.presence
      service.update!(update_schedule_cron: cron)
      respond_with_card(service)
    end

    private

    def respond_with_card(service, status: :ok)
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("service_#{service.name}", partial: "admin/services/service_card", locals: { service: service }), status: status }
        format.html         { head status }
        format.json         { render json: service.as_json, status: status }
      end
    end

    def regions_dir
      ENV.fetch("REGIONS_DIR") do
        candidates = [Rails.root.join("regions"), Rails.root.join("..", "regions")]
        candidates.find { |p| File.directory?(p) } || candidates.first
      end
    end
  end
end
