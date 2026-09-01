require "swagger_helper"

RSpec.describe "Admin::Apply", type: :request do
  path "/admin/apply", swagger_doc: "admin/swagger.yaml" do
    post "Apply current selection (two-phase)" do
      tags "Admin"
      security [basicAuth: []]
      produces "application/json"

      parameter name: :confirmed, in: :query, type: :string, required: false, example: "true"

      response "409", "confirmation required" do
        schema "$ref" => "#/components/schemas/ApplyProjectionResponse"

        let(:Authorization) { ActionController::HttpAuthentication::Basic.encode_credentials("admin", "x") }

        before do
          stub_const("ADMIN_CHECK_OK", true)
          ENV["ADMIN_USERNAME"] = "admin"
          ENV["ADMIN_PASSWORD"] = "x"

          fake_region = RegionCatalog::Region.new(name: "berlin", label: "Berlin", country_code: "de", pbf_urls: [], default_view: {})
          fake_catalog = instance_double(RegionCatalog, names: %w[berlin])
          allow(fake_catalog).to receive(:find).and_return(fake_region)
          allow(RegionCatalog).to receive(:load_dir).and_return(fake_catalog)

          RegionSelection.create!(region_name: "berlin", active: true, position: 0)
        end

        let(:confirmed) { nil }
        run_test!
      end
    end
  end
end
