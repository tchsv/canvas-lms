# frozen_string_literal: true

#
# Copyright (C) 2022 - present Instructure, Inc.
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

describe OutcomesFeaturesHelper do
  include OutcomesFeaturesHelper

  before :once do
    @account = Account.default
    @context = @course = @account.courses.create!
    @global_outcome = outcome_model(global: true, title: "Global outcome")
    @account_outcome = outcome_model(context: @account)
    @course_outcome = outcome_model(context: @course)
  end

  describe "#account_level_mastery_scales_enabled?" do
    before do
      @context.root_account.enable_feature!(:account_level_mastery_scales)
    end

    it "returns true when account_level_mastery_scales FF is enabled" do
      expect(account_level_mastery_scales_enabled?(@course_outcome.context)).to eq true
    end

    it "returns false when account_level_mastery_scales FF is disabled" do
      @context.root_account.disable_feature!(:account_level_mastery_scales)
      expect(account_level_mastery_scales_enabled?(@course_outcome.context)).to eq false
    end

    it "works properly when arg is course outcome" do
      expect(account_level_mastery_scales_enabled?(@course_outcome.context)).to eq true
      @context.root_account.disable_feature!(:account_level_mastery_scales)
      expect(account_level_mastery_scales_enabled?(@course_outcome.context)).to eq false
    end

    it "works properly when arg is account outcome" do
      expect(account_level_mastery_scales_enabled?(@account_outcome.context)).to eq true
      @context.root_account.disable_feature!(:account_level_mastery_scales)
      expect(account_level_mastery_scales_enabled?(@account_outcome.context)).to eq false
    end

    it "works properly when arg is global outcome" do
      expect(account_level_mastery_scales_enabled?(@global_outcome.context)).to eq nil
      @context.root_account.disable_feature!(:account_level_mastery_scales)
      expect(account_level_mastery_scales_enabled?(@global_outcome.context)).to eq nil
    end
  end
end
