# frozen_string_literal: true

#
# Copyright (C) 2020 - present Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.
#
require_relative "../spec_helper"
require "webmock/rspec"

describe CanvasOutcomesHelper do
  subject { Object.new.extend CanvasOutcomesHelper }

  around do |example|
    WebMock.disable_net_connect!(allow_localhost: true)
    example.run
    WebMock.enable_net_connect!
  end

  before do
    course_with_teacher_logged_in(active_all: true)
  end

  let(:account) { @course.account }

  def create_page(attrs)
    page = @course.wiki_pages.create!(attrs)
    page.publish! if page.unpublished?
    page
  end

  describe "#set_outcomes_alignment_js_env" do
    let(:wiki_page) { create_page title: "title text", body: "body text" }

    context "without outcomes" do
      it "does not set JS_ENV" do
        expect(subject).not_to receive(:js_env)
        subject.set_outcomes_alignment_js_env(wiki_page, account, {})
      end
    end

    context "with outcomes" do
      before do
        outcome_model(context: account)
      end

      it "raises error on invalid artifact type" do
        expect { subject.set_outcomes_alignment_js_env(account, account, {}) }.to raise_error("Unsupported artifact type: Account")
      end

      shared_examples_for "valid js_env settings" do
        it "sets js_env values" do
          expect(subject).to receive(:extract_domain_jwt).and_return ["domain", "jwt"]
          expect(subject).to receive(:js_env).with({
                                                     canvas_outcomes: {
                                                       artifact_type: "canvas.page",
                                                       artifact_id: wiki_page.id,
                                                       context_uuid: account.uuid,
                                                       host: expected_host,
                                                       jwt: "jwt",
                                                       extra_key: "extra_value"
                                                     }
                                                   })
          subject.set_outcomes_alignment_js_env(wiki_page, account, extra_key: "extra_value")
        end
      end

      context "without overriding protocol" do
        let(:expected_host) { "http://domain" }

        it_behaves_like "valid js_env settings"
      end

      context "overriding protocol" do
        let(:expected_host) { "https://domain" }

        before do
          ENV["OUTCOMES_SERVICE_PROTOCOL"] = "https"
        end

        after do
          ENV.delete("OUTCOMES_SERVICE_PROTOCOL")
        end

        it_behaves_like "valid js_env settings"
      end

      context "within a Group" do
        before do
          outcome_model(context: @course)
          @group = @course.groups.create(name: "some group")
        end

        it "sets js_env with the group.context values" do
          expect(subject).to receive(:extract_domain_jwt).and_return ["domain", "jwt"]
          expect(subject).to receive(:js_env).with({
                                                     canvas_outcomes: {
                                                       artifact_type: "canvas.page",
                                                       artifact_id: wiki_page.id,
                                                       context_uuid: @course.uuid,
                                                       host: "http://domain",
                                                       jwt: "jwt"
                                                     }
                                                   })
          subject.set_outcomes_alignment_js_env(wiki_page, @group, {})
        end
      end
    end
  end

  describe "#extract_domain_jwt" do
    it "returns nil domain and jwt with no provision settings" do
      expect(subject.extract_domain_jwt(account, "")).to eq [nil, nil]
    end

    it "returns nil domain and jwt with no outcomes provision settings" do
      account.settings[:provision] = {}
      account.save!
      expect(subject.extract_domain_jwt(account, "")).to eq [nil, nil]
    end

    it "returns domain and jwt with outcomes provision settings" do
      settings = { consumer_key: "key", jwt_secret: "secret", domain: "domain" }
      account.settings[:provision] = { "outcomes" => settings }
      account.save!
      expect(JWT).to receive(:encode).and_return "encoded"
      expect(subject.extract_domain_jwt(account, "")).to eq ["domain", "encoded"]
    end

    describe "if ApplicationController.test_cluster_name is specified" do
      it "returns a domain using the test_cluster_name domain" do
        settings = { consumer_key: "key", jwt_secret: "secret", domain: "domain",
                     beta_domain: "beta.domain" }
        account.settings[:provision] = { "outcomes" => settings }
        account.save!
        expect(JWT).to receive(:encode).and_return "encoded"
        allow(ApplicationController).to receive(:test_cluster?).and_return(true)
        allow(ApplicationController).to receive(:test_cluster_name).and_return("beta")
        expect(subject.extract_domain_jwt(account, "")).to eq ["beta.domain", "encoded"]
        allow(ApplicationController).to receive(:test_cluster_name).and_return("invalid")
        expect(subject.extract_domain_jwt(account, "")).to eq [nil, nil]
      end
    end
  end

  describe "#get_lmgb_results" do
    context "without account outcome settings" do
      it "returns nil with no provision settings" do
        expect(subject.get_lmgb_results(account, "1", "assign.type", "1")).to eq nil
      end

      it "returns nil with no outcome provision settings" do
        account.settings[:provision] = {}
        account.save!
        expect(subject.get_lmgb_results(account, "1", "assign.type", "1")).to eq nil
      end
    end

    context "with account outcome settings" do
      before do
        settings = { consumer_key: "key", jwt_secret: "secret", domain: "domain" }
        account.settings[:provision] = { "outcomes" => settings }
        account.save!
      end

      context "without assignment ids" do
        it "returns nil when assignment ids is nil" do
          expect(subject.get_lmgb_results(account, nil, "assign.type", "1")).to eq nil
        end

        it "returns nil when assignment ids is empty" do
          expect(subject.get_lmgb_results(account, "", "assign.type", "1")).to eq nil
        end
      end

      context "without assignment type" do
        it "returns nil when assignment type is nil" do
          expect(subject.get_lmgb_results(account, "1", nil, "1")).to eq nil
        end

        it "returns nil when assignment type is empty" do
          expect(subject.get_lmgb_results(account, "1", "", "1")).to eq nil
        end
      end

      context "without outcome ids type" do
        it "returns nil when outcome ids is nil" do
          expect(subject.get_lmgb_results(account, "1", "assign.type", nil)).to eq nil
        end

        it "returns nil when outcome ids is empty" do
          expect(subject.get_lmgb_results(account, "1", "assign.type", "")).to eq nil
        end
      end

      context "with outcomes provision settings" do
        def stub_get_lmgb_results(params)
          stub_request(:get, "http://domain/api/authoritative_results?#{params}").with({
                                                                                         headers: {
                                                                                           Authorization: /\+*/,
                                                                                           Accept: "*/*",
                                                                                           "Accept-Encoding": /\+*/,
                                                                                           "User-Agent": "Ruby"
                                                                                         }
                                                                                       })
        end

        context "with outcome_service_results_to_canvas FF on" do
          before do
            @course.enable_feature!(:outcome_service_results_to_canvas)
          end

          it "raises error on non 2xx response" do
            stub_get_lmgb_results("associated_asset_id_list=1&associated_asset_type=assign.type&external_outcome_id_list=1").to_return(status: 401, body: '{"valid_jwt":false}')
            expect { subject.get_lmgb_results(@course, "1", "assign.type", "1") }.to raise_error(RuntimeError, /Error retrieving results from Outcomes Service:/)
          end

          it "returns results with one assignment id" do
            stub_get_lmgb_results("associated_asset_id_list=1&associated_asset_type=assign.type&external_outcome_id_list=1").to_return(status: 200, body: '{"results":[{"result":"stuff"}]}')
            expect(subject.get_lmgb_results(@course, "1", "assign.type", "1")).to eq [{ "result" => "stuff" }]
          end

          it "returns results with multiple assignment ids" do
            stub_get_lmgb_results("associated_asset_id_list=1,2&associated_asset_type=assign.type&external_outcome_id_list=1").to_return(status: 200, body: '{"results":[{"result_one":"stuff1"},{"result_two":"stuff2"}]}')
            expect(subject.get_lmgb_results(@course, "1,2", "assign.type", "1")).to eq [{ "result_one" => "stuff1" }, { "result_two" => "stuff2" }]
          end

          it "returns results with one outcome id" do
            stub_get_lmgb_results("associated_asset_id_list=1,2&associated_asset_type=assign.type&external_outcome_id_list=1").to_return(status: 200, body: '{"results":[{"result_one":"stuff"}]}')
            expect(subject.get_lmgb_results(@course, "1,2", "assign.type", "1")).to eq [{ "result_one" => "stuff" }]
          end

          it "returns results with multiple outcome ids" do
            stub_get_lmgb_results("associated_asset_id_list=1,2&associated_asset_type=assign.type&external_outcome_id_list=1,2").to_return(status: 200, body: '{"results":[{"result_one":"stuff1"},{"result_two":"stuff2"}]}')
            expect(subject.get_lmgb_results(@course, "1,2", "assign.type", "1,2")).to eq [{ "result_one" => "stuff1" }, { "result_two" => "stuff2" }]
          end

          it "returns empty array when assignment type is not matched" do
            stub_get_lmgb_results("associated_asset_id_list=1&associated_asset_type=assign.type.no.match&external_outcome_id_list=1").to_return(status: 200, body: '{"results":[]}')
            expect(subject.get_lmgb_results(@course, "1", "assign.type.no.match", "1")).to eq []
          end

          it "returns empty array when assignment ids are not matched" do
            stub_get_lmgb_results("associated_asset_id_list=4,5&associated_asset_type=assign.type&external_outcome_id_list=1").to_return(status: 200, body: '{"results":[]}')
            expect(subject.get_lmgb_results(@course, "4,5", "assign.type", "1")).to eq []
          end

          it "returns empty array when no outcome ids are matched" do
            stub_get_lmgb_results("associated_asset_id_list=1&associated_asset_type=assign.type&external_outcome_id_list=5").to_return(status: 200, body: '{"results":[]}')
            expect(subject.get_lmgb_results(@course, "1", "assign.type", "5")).to eq []
          end
        end

        context "with outcome_service_results_to_canvas FF off" do
          before do
            @course.disable_feature!(:outcome_service_results_to_canvas)
          end

          it "returns nil when FF is off" do
            expect(subject.get_lmgb_results(@course, "1", "assign.type", "1")).to eq nil
          end
        end
      end
    end
  end

  describe "#build_request_url" do
    it "add params if present" do
      params = { param: "stuff" }
      expect(subject.build_request_url("protocol", "domain", "endpoint", params)).to eq "protocol://domain/endpoint?param=stuff"
    end

    it "does not add params when not present" do
      params = {}
      expect(subject.build_request_url("protocol", "domain", "endpoint", params)).to eq "protocol://domain/endpoint"
      params = nil
      expect(subject.build_request_url("protocol", "domain", "endpoint", params)).to eq "protocol://domain/endpoint"
    end
  end
end
