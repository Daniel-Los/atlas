require "swagger_helper"

RSpec.describe "Admin::Services", type: :request do
  path "/admin/services/{name}", swagger_doc: "admin/swagger.yaml" do
    parameter name: :name, in: :path, type: :string

    post "Enable or disable a service" do
      tags "Admin"
      security [basicAuth: []]
      consumes "application/x-www-form-urlencoded"
      produces "application/json"

      parameter name: :enabled, in: :formData, type: :string, required: true, example: "true"

      response "200", "service toggled" do
        let(:name)    { "photon" }
        let(:enabled) { "true" }
        let(:Authorization) { ActionController::HttpAuthentication::Basic.encode_credentials("admin", "x") }

        before do
          stub_const("ADMIN_CHECK_OK", true)
          ENV["ADMIN_USERNAME"] = "admin"
          ENV["ADMIN_PASSWORD"] = "x"
          Service.create!(name: "photon", profile: "geocoding")
          allow_any_instance_of(ControlPlaneClient).to receive(:enable!).and_return(true)
        end

        run_test!
      end
    end
  end
end
