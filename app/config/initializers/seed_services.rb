Rails.application.config.after_initialize do
  next if Rails.env.test?

  known = {
    "photon"      => "geocoding",
    "placeholder" => "geocoding",
    "libpostal"   => "geocoding",
    "valhalla"    => "routing",
    "overpass"    => "pois",
    "otp"         => "transit"
  }.freeze

  begin
    next unless ActiveRecord::Base.connection.table_exists?(:services)
    known.each do |name, profile|
      Service.find_or_create_by!(name: name) { |s| s.profile = profile }
    end
  rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::StatementInvalid => e
    Rails.logger.warn("seed_services skipped: #{e.class.name.demodulize}: #{e.message}")
  end
end
