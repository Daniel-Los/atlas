module Admin
  class ApplyController < BaseController
    def create
      intents  = parse_intents
      catalog  = RegionCatalog.load_dir(regions_dir)
      regions  = RegionSelection.active_names.map { |n| catalog.find(n) }

      # Project size/time using the post-apply service set so the confirmation
      # reflects what the user actually asked for.
      future_services = projected_service_names(intents)
      proj = ApplyProjection.new(regions: regions, services: future_services).summary

      if params[:confirmed].present? && ActiveModel::Type::Boolean.new.cast(params[:confirmed])
        apply_service_intents!(intents)
        ControlPlaneClient.default.apply_regions(regions.map(&:name)) unless regions.empty?
        Service.where(name: %w[valhalla overpass otp]).where(enabled: true).update_all(status: Service.statuses[:starting])
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.update(
              "apply_confirmation",
              partial: "admin/apply/applied",
              locals: { projection: proj, intents: intents }
            ), status: :accepted
          end
          format.json { render json: { ok: true, projection: proj.to_h, intents: intents }, status: :accepted }
          format.html { head :accepted }
        end
      else
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.update(
              "apply_confirmation",
              partial: "admin/apply/confirmation",
              locals: { projection: proj, intents: intents }
            ), status: :conflict
          end
          format.json { render json: { projection: proj.to_h, intents: intents }, status: :conflict }
          format.html { render plain: proj.to_h.to_json, status: :conflict }
        end
      end
    end

    private

    # Accept intents from either form params (Confirm form re-POST) or JSON body
    # (initial Save & apply fetch). Filter to known service names and coerce
    # `enabled` to a real boolean.
    def parse_intents
      raw = params[:service_intents]
      raw = JSON.parse(request.raw_post)["service_intents"] if raw.blank? && request.content_type&.include?("json") && request.raw_post.present?
      raw.to_a.filter_map do |i|
        i = i.to_unsafe_h if i.respond_to?(:to_unsafe_h)
        name    = i["name"] || i[:name]
        enabled = ActiveModel::Type::Boolean.new.cast(i["enabled"] || i[:enabled])
        next nil if name.blank?
        next nil unless Service.exists?(name: name)
        { name: name, enabled: enabled }
      end
    rescue JSON::ParserError
      []
    end

    def projected_service_names(intents)
      enabled_set = Service.where(enabled: true).pluck(:name).to_set
      intents.each { |i| i[:enabled] ? enabled_set.add(i[:name]) : enabled_set.delete(i[:name]) }
      enabled_set.to_a
    end

    def apply_service_intents!(intents)
      intents.each do |intent|
        service = Service.find_by(name: intent[:name])
        next unless service
        wanted = intent[:enabled]
        next if service.enabled == wanted
        Service.transaction do
          service.update!(enabled: wanted)
          if wanted
            ControlPlaneClient.default.enable!(service.name)
          else
            ControlPlaneClient.default.disable!(service.name)
          end
        end
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
