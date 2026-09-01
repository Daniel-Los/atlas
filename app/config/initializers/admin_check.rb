Rails.application.config.after_initialize do
  ADMIN_CHECK_OK = ENV["ADMIN_USERNAME"].present? && ENV["ADMIN_PASSWORD"].present?
end
