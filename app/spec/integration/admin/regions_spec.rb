require "swagger_helper"

RSpec.describe "Admin::Regions", type: :request do
  path "/admin/regions", swagger_doc: "admin/swagger.yaml" do
    post "Replace region selection" do
      tags "Admin"
      security [basicAuth: []]
      consumes "application/json"
      produces "application/json"

      parameter name: :body, in: :body, schema: {
        type: :object, required: %w[regions],
        properties: { regions: { type: :array, items: { type: :string } } }
      }

      response "200", "selection replaced" do
        let(:body) { { regions: %w[berlin] } }
        let(:Authorization) { ActionController::HttpAuthentication::Basic.encode_credentials("admin", "x") }

        before do
          stub_const("ADMIN_CHECK_OK", true)
          ENV["ADMIN_USERNAME"] = "admin"
          ENV["ADMIN_PASSWORD"] = "x"

          fake_region = RegionCatalog::Region.new(name: "berlin", label: "Berlin", country_code: "de", pbf_urls: [], default_view: {})
          fake_catalog = instance_double(RegionCatalog, names: %w[berlin])
          allow(fake_catalog).to receive(:find).and_return(fake_region)
          allow(RegionCatalog).to receive(:load_dir).and_return(fake_catalog)
        end

        run_test!
      end
    end
  end
end
