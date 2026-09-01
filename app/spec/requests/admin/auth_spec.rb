require "rails_helper"

RSpec.describe "Admin auth", type: :request do
  describe "when env vars set" do
    before do
      stub_const("ADMIN_CHECK_OK", true)
      ENV["ADMIN_USERNAME"] = "admin"
      ENV["ADMIN_PASSWORD"] = "secret"
    end

    after do
      ENV.delete("ADMIN_USERNAME")
      ENV.delete("ADMIN_PASSWORD")
    end

    it "returns 401 without credentials" do
      get "/admin/services"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 200 with correct credentials" do
      get "/admin/services", headers: { "HTTP_AUTHORIZATION" =>
        ActionController::HttpAuthentication::Basic.encode_credentials("admin", "secret") }
      expect(response).to have_http_status(:ok)
    end

    it "returns 401 with wrong credentials" do
      get "/admin/services", headers: { "HTTP_AUTHORIZATION" =>
        ActionController::HttpAuthentication::Basic.encode_credentials("admin", "WRONG") }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "when env vars are missing" do
    before { stub_const("ADMIN_CHECK_OK", false) }

    it "returns 503 explaining the misconfig" do
      get "/admin/services"
      expect(response).to have_http_status(:service_unavailable)
      expect(response.body).to include("ADMIN_USERNAME")
    end
  end

  describe "home page integration" do
    it "does not include the admin panel by default" do
      get "/"
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('data-controller="panel"')
    end

    it "includes a settings affordance inline in the side panel" do
      get "/"
      # The standalone /admin/services cog was replaced by an inline settings
      # tab in the side-panel rail. Verify the affordance still exists.
      expect(response.body).to include('data-tab="settings"')
      expect(response.body).to include('aria-label="Settings"')
    end
  end
end
