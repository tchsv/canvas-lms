# frozen_string_literal: true

#
# Copyright (C) 2021 - present Instructure, Inc.
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

describe CoursePace do
  before :once do
    course_with_student active_all: true
    @course.update start_at: "2021-09-01", restrict_enrollments_to_course_dates: true, time_zone: "America/Denver"
    @course.root_account.enable_feature!(:course_paces)
    @course.enable_course_paces = true
    @course.save!
    @module = @course.context_modules.create!
    @assignment = @course.assignments.create!
    @course_section = @course.course_sections.first
    @tag = @assignment.context_module_tags.create! context_module: @module, context: @course, tag_type: "context_module"
    @course_pace = @course.course_paces.create! workflow_state: "active"
    @course_pace_module_item = @course_pace.course_pace_module_items.create! module_item: @tag
    @unpublished_assignment = @course.assignments.create! workflow_state: "unpublished"
    @unpublished_tag = @unpublished_assignment.context_module_tags.create! context_module: @module, context: @course, tag_type: "context_module", workflow_state: "unpublished"
  end

  context "associations" do
    it "has functioning course association" do
      expect(@course.course_paces).to match_array([@course_pace])
      expect(@course_pace.course).to eq @course
    end

    it "has functioning course_pace_module_items association" do
      expect(@course_pace.course_pace_module_items.map(&:module_item)).to match_array([@tag, @unpublished_tag])
    end
  end

  context "scopes" do
    before :once do
      @other_section = @course.course_sections.create! name: "other_section"
      @section_plan = @course.course_paces.create! course_section: @other_section
      @student_plan = @course.course_paces.create! user: @student
    end

    it "has a working primary scope" do
      expect(@course.course_paces.primary).to match_array([@course_pace])
    end

    it "has a working for_user scope" do
      expect(@course.course_paces.for_user(@student)).to match_array([@student_plan])
    end

    it "has a working for_section scope" do
      expect(@course.course_paces.for_section(@other_section)).to match_array([@section_plan])
    end
  end

  context "course_pace_context" do
    it "requires a course" do
      bad_plan = CoursePace.create
      expect(bad_plan).not_to be_valid

      bad_plan.course = course_factory
      expect(bad_plan).to be_valid
    end

    it "disallows a user and section simultaneously" do
      course_with_student
      bad_plan = @course.course_paces.build(user: @student, course_section: @course.default_section)
      expect(bad_plan).not_to be_valid

      bad_plan.course_section = nil
      expect(bad_plan).to be_valid
    end
  end

  context "constraints" do
    it "has a unique constraint on course for active primary course paces" do
      expect { @course.course_paces.create! workflow_state: "active" }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "has a unique constraint for active section course paces" do
      @course.course_paces.create! course_section: @course.default_section, workflow_state: "active"
      expect do
        @course.course_paces.create! course_section: @course.default_section, workflow_state: "active"
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "has a unique constraint for active student course paces" do
      @course.course_paces.create! user: @student, workflow_state: "active"
      expect do
        @course.course_paces.create! user: @student, workflow_state: "active"
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  context "root_account" do
    it "infers root_account_id from course" do
      expect(@course_pace.root_account).to eq @course.root_account
    end
  end

  context "duplicate" do
    it "returns an initialized duplicate of the course pace" do
      duplicate_course_pace = @course_pace.duplicate
      expect(duplicate_course_pace.class).to eq(CoursePace)
      expect(duplicate_course_pace.persisted?).to eq(false)
      expect(duplicate_course_pace.id).to eq(nil)
    end

    it "supports passing in options" do
      opts = { user_id: 1 }
      duplicate_course_pace = @course_pace.duplicate(opts)
      expect(duplicate_course_pace.user_id).to eq(opts[:user_id])
      expect(duplicate_course_pace.course_section_id).to eq(opts[:course_section_id])
    end
  end

  context "publish" do
    def fancy_midnight_rounded_to_last_second(date)
      (CanvasTime.fancy_midnight(date.to_datetime).to_time - 1.second).round
    end

    before :once do
      @course_pace.update! end_date: "2021-09-30"
    end

    it "creates an override for students" do
      expect(@assignment.due_at).to eq(nil)
      expect(@unpublished_assignment.due_at).to eq(nil)
      expect(@course_pace.publish).to eq(true)
      expect(AssignmentOverride.count).to eq(2)
    end

    it "creates assignment overrides for the course pace user" do
      @course_pace.update(user_id: @student)
      expect(AssignmentOverride.count).to eq(0)
      expect(@course_pace.publish).to eq(true)
      expect(AssignmentOverride.count).to eq(2)
      @course.assignments.each do |assignment|
        assignment_override = assignment.assignment_overrides.first
        expect(assignment_override.due_at).to eq(fancy_midnight_rounded_to_last_second("2021-09-01"))
        expect(assignment_override.assignment_override_students.first.user_id).to eq(@student.id)
      end
    end

    it "removes the user from an adhoc assignment override if it includes other students" do
      student2 = user_model
      StudentEnrollment.create!(user: student2, course: @course)
      assignment_override = @assignment.assignment_overrides.create(
        title: "ADHOC Test",
        workflow_state: "active",
        set_type: "ADHOC",
        due_at: fancy_midnight_rounded_to_last_second("2021-09-05"),
        due_at_overridden: true
      )
      assignment_override.assignment_override_students << AssignmentOverrideStudent.new(user_id: @student, no_enrollment: false)
      assignment_override.assignment_override_students << AssignmentOverrideStudent.new(user_id: student2, no_enrollment: false)

      @course_pace.update(user_id: @student)
      expect(@assignment.assignment_overrides.count).to eq(1)
      assignment_override = @assignment.assignment_overrides.first
      expect(assignment_override.due_at).to eq(fancy_midnight_rounded_to_last_second("2021-09-05"))
      expect(assignment_override.assignment_override_students.pluck(:user_id)).to eq([@student.id, student2.id])
      expect(@course_pace.publish).to eq(true)
      expect(@assignment.assignment_overrides.count).to eq(2)
      expect(assignment_override.due_at).to eq(fancy_midnight_rounded_to_last_second("2021-09-05"))
      expect(assignment_override.assignment_override_students.pluck(:user_id)).to eq([student2.id])
      assignment_override2 = @assignment.assignment_overrides.second
      expect(assignment_override2.due_at).to eq(fancy_midnight_rounded_to_last_second("2021-09-01"))
      expect(assignment_override2.assignment_override_students.pluck(:user_id)).to eq([@student.id])
    end

    it "adds the user to an adhoc assignment override if it already exists for that date" do
      # The due_at times are stored in the databas as UTC times, so we need to convert the timezone to UTC
      assignment_override = @assignment.assignment_overrides.create!(
        title: "ADHOC Test",
        workflow_state: "active",
        set_type: "ADHOC",
        due_at: fancy_midnight_rounded_to_last_second("2021-09-01"),
        due_at_overridden: true
      )
      assignment_override.assignment_override_students << AssignmentOverrideStudent.new(user_id: @student, no_enrollment: false)
      assignment_override2 = @assignment.assignment_overrides.create!(
        title: "ADHOC Test",
        workflow_state: "active",
        set_type: "ADHOC",
        due_at: fancy_midnight_rounded_to_last_second("2021-09-06"),
        due_at_overridden: true
      )
      student2 = user_model
      StudentEnrollment.create!(user: student2, course: @course)
      assignment_override2.assignment_override_students << AssignmentOverrideStudent.new(user_id: student2, no_enrollment: false)
      expect(@assignment.assignment_overrides.active.count).to eq(2)
      expect(@course_pace.publish).to eq(true)
      expect(@assignment.assignment_overrides.active.count).to eq(1)
      assignment_override = @assignment.assignment_overrides.active.first
      # We need to round to the last whole second to ensure the due_at is the same
      expect(assignment_override.due_at).to eq(fancy_midnight_rounded_to_last_second("2021-09-01"))
      expect(assignment_override.assignment_override_students.pluck(:user_id).sort).to eq([@student.id, student2.id])
    end

    it "creates assignment overrides for the course pace course section" do
      @course_pace.update(course_section: @course_section)
      expect(@assignment.assignment_overrides.count).to eq(0)
      expect(@course_pace.publish).to eq(true)
      expect(@assignment.assignment_overrides.count).to eq(1)
      assignment_override = @assignment.assignment_overrides.first
      expect(assignment_override.due_at).to eq(fancy_midnight_rounded_to_last_second("2021-09-01"))
      expect(assignment_override.assignment_override_students.first.user_id).to eq(@student.id)
    end

    it "updates overrides that are already present if the days have changed" do
      @course_pace.publish
      assignment_override = @assignment.assignment_overrides.first
      expect(assignment_override.due_at).to eq(fancy_midnight_rounded_to_last_second("2021-09-01"))
      @course_pace_module_item.update duration: 2
      @course_pace.publish
      assignment_override.reload
      expect(assignment_override.due_at).to eq(fancy_midnight_rounded_to_last_second("2021-09-03"))
    end

    it "updates user overrides that are already present if the days have changed" do
      @course_pace.update(user_id: @student)
      @course_pace.publish
      expect(@assignment.assignment_overrides.active.count).to eq(1)
      @course_pace_module_item.update duration: 2
      @course_pace.publish
      expect(@assignment.assignment_overrides.active.count).to eq(1)
      assignment_override = @assignment.assignment_overrides.active.first
      expect(assignment_override.due_at).to eq(fancy_midnight_rounded_to_last_second("2021-09-03"))
      expect(assignment_override.assignment_override_students.first.user_id).to eq(@student.id)
    end

    it "updates course section overrides that are already present if the days have changed" do
      @course_pace.update(course_section: @course_section)
      @course_pace.publish
      expect(@assignment.assignment_overrides.active.count).to eq(1)
      @course_pace_module_item.update duration: 2
      @course_pace.publish
      expect(@assignment.assignment_overrides.active.count).to eq(1)
      assignment_override = @assignment.assignment_overrides.active.first
      expect(assignment_override.due_at).to eq(fancy_midnight_rounded_to_last_second("2021-09-03"))
      expect(assignment_override.assignment_override_students.first.user_id).to eq(@student.id)
    end

    it "does not change assignment due date when user course pace is published if an assignment override already exists" do
      @course_pace.publish
      assignment_override = @assignment.assignment_overrides.first
      expect(assignment_override.due_at).to eq(fancy_midnight_rounded_to_last_second("2021-09-01"))
      expect(@assignment.assignment_overrides.active.count).to eq(1)

      student_course_pace = @course.course_paces.create!(user: @student, workflow_state: "active")
      student_course_pace.publish
      assignment_override.reload
      expect(assignment_override.due_at).to eq(fancy_midnight_rounded_to_last_second("2021-09-01"))
      expect(@assignment.assignment_overrides.active.count).to eq(1)
    end

    it "sets overrides for graded discussions" do
      topic = graded_discussion_topic(context: @course)
      topic_tag = @module.add_item type: "discussion_topic", id: topic.id
      @course_pace.course_pace_module_items.create! module_item: topic_tag
      expect(topic.assignment.assignment_overrides.count).to eq 0
      expect(@course_pace.publish).to eq(true)
      expect(topic.assignment.assignment_overrides.count).to eq 1
    end

    it "does not change overrides for students that have course paces if the course pace is published" do
      expect(@course_pace.publish).to eq(true)
      expect(@assignment.assignment_overrides.active.count).to eq(1)
      assignment_override = @assignment.assignment_overrides.active.first
      expect(assignment_override.due_at).to eq(fancy_midnight_rounded_to_last_second("2021-09-01"))
      # Publish student specific course pace and verify dates have changed
      student_course_pace = @course.course_paces.create! user: @student, workflow_state: "active"
      @course.student_enrollments.find_by(user: @student).update(start_at: "2021-09-06")
      student_course_pace.course_pace_module_items.create! module_item: @tag
      expect(student_course_pace.publish).to eq(true)
      assignment_override.reload
      expect(assignment_override.due_at).to eq(fancy_midnight_rounded_to_last_second("2021-09-06"))
      # Republish course pace and verify dates have not changed on student specific override
      @course_pace.instance_variable_set(:@student_enrollments, nil)
      expect(@course_pace.publish).to eq(true)
      assignment_override.reload
      expect(assignment_override.due_at).to eq(fancy_midnight_rounded_to_last_second("2021-09-06"))
    end

    it "does not change overrides for sections that have course paces if the course pace is published" do
      expect(@course_pace.publish).to eq(true)
      expect(@assignment.assignment_overrides.active.count).to eq(1)
      assignment_override = @assignment.assignment_overrides.active.first
      expect(assignment_override.due_at).to eq(fancy_midnight_rounded_to_last_second("2021-09-01"))
      # Publish course section specific course pace and verify dates have changed
      @course_section.update(start_at: "2021-09-06")
      section_course_pace = @course.course_paces.create! course_section: @course_section, workflow_state: "active"
      section_course_pace.course_pace_module_items.create! module_item: @tag
      expect(section_course_pace.publish).to eq(true)
      assignment_override.reload
      expect(assignment_override.due_at).to eq(fancy_midnight_rounded_to_last_second("2021-09-06"))
      # Republish course pace and verify dates have not changed on student specific override
      @course_pace.instance_variable_set(:@student_enrollments, nil)
      expect(@course_pace.publish).to eq(true)
      assignment_override.reload
      expect(assignment_override.due_at).to eq(fancy_midnight_rounded_to_last_second("2021-09-06"))
    end

    it "does not change overrides for students that have course paces if the course section course pace is published" do
      @course_pace.update(course_section: @course_section)
      expect(@course_pace.publish).to eq(true)
      expect(@assignment.assignment_overrides.active.count).to eq(1)
      assignment_override = @assignment.assignment_overrides.active.first
      expect(assignment_override.due_at).to eq(fancy_midnight_rounded_to_last_second("2021-09-01"))
      # Publish student specific course pace and verify dates have changed
      @course.student_enrollments.find_by(user: @student).update(start_at: "2021-09-06")
      student_course_pace = @course.course_paces.create! user: @student, workflow_state: "active"
      student_course_pace.course_pace_module_items.create! module_item: @tag
      expect(student_course_pace.publish).to eq(true)
      assignment_override.reload
      expect(assignment_override.due_at).to eq(fancy_midnight_rounded_to_last_second("2021-09-06"))
      # Republish course pace and verify dates have not changed on student specific override
      @course_pace.instance_variable_set(:@student_enrollments, nil)
      expect(@course_pace.publish).to eq(true)
      assignment_override.reload
      expect(assignment_override.due_at).to eq(fancy_midnight_rounded_to_last_second("2021-09-06"))
    end
  end

  describe "default plan start_at" do
    orig_zone = Time.zone
    before do
      @course.update start_at: nil
      @course_pace.user_id = nil
      Time.zone = @course.time_zone
    end

    after do
      Time.zone = orig_zone
    end

    it "returns student enrollment date, if working on behalf of a student" do
      student3 = user_model
      enrollment = StudentEnrollment.create!(user: student3, course: @course)
      enrollment.update start_at: "2022-01-29"
      @course_pace.user_id = student3.id
      expect(@course_pace.start_date.to_date).to eq(Date.parse("2022-01-29"))

      result = @course_pace.start_date(with_context: true)
      expect(result[:start_date].to_date).to eq(Date.parse("2022-01-29"))
      expect(result[:start_date_context]).to eq("user")
    end

    it "returns section start if available" do
      other_section = @course.course_sections.create! name: "other_section", start_at: "2022-01-30"
      section_plan = @course.course_paces.create! course_section: other_section
      expect(section_plan.start_date.to_date).to eq(Date.parse("2022-01-30"))

      result = section_plan.start_date(with_context: true)
      expect(result[:start_date].to_date).to eq(Date.parse("2022-01-30"))
      expect(result[:start_date_context]).to eq("section")
    end

    it "returns course start if available" do
      @course.update start_at: "2022-01-28"
      expect(@course_pace.start_date.to_date).to eq(Date.parse("2022-01-28"))

      result = @course_pace.start_date(with_context: true)
      expect(result[:start_date].to_date).to eq(Date.parse("2022-01-28"))
      expect(result[:start_date_context]).to eq("course")
    end

    it "returns course's term start if available" do
      @course.enrollment_term.update start_at: Time.zone.parse("2022-01-27")
      expect(@course_pace.start_date.to_date).to eq(Date.parse("2022-01-27"))

      result = @course_pace.start_date(with_context: true)
      expect(result[:start_date].to_date).to eq(Date.parse("2022-01-27"))
      expect(result[:start_date_context]).to eq("term")
    end

    it "returns today date as a last resort" do
      # there's an extremely tiny window where the date may have changed between
      # when start_date called Time.now and now causing this to fail
      # I don't think it's worth worrying about.
      expect(@course_pace.start_date.to_date).to eq(Time.now.to_date)

      result = @course_pace.start_date(with_context: true)
      expect(result[:start_date].to_date).to eq(Time.now.to_date)
      expect(result[:start_date_context]).to eq("hypothetical")
    end
  end

  describe "default plan effective_end_at" do
    orig_zone = Time.zone
    before do
      @course.update start_at: nil
      @course_pace.user_id = nil
      @student = create_users(1, return_type: :record).first
      @course.enroll_student(@student, enrollment_state: "active")
    end

    after do
      Time.zone = orig_zone
    end

    it "returns hard end date if set" do
      @course_pace.hard_end_dates = true
      @course_pace[:end_date] = "2022-03-17"
      result = @course_pace.effective_end_date(with_context: true)
      expect(result[:end_date].to_date).to eq(Date.parse("2022-03-17"))
      expect(result[:end_date_context]).to eq("hard")
    end

    it "returns plan's end_date from db if a student plan" do
      @course_pace[:end_date] = "2022-03-17"
      @course_pace[:user_id] = @student.id
      result = @course_pace.effective_end_date(with_context: true)
      expect(result[:end_date].to_date).to eq(Date.parse("2022-03-17"))
      expect(result[:end_date_context]).to eq("user")
    end

    it "returns course end if available" do
      @course.update conclude_at: Time.zone.parse("2022-01-28T13:00:00")
      result = @course_pace.effective_end_date(with_context: true)
      expect(result[:end_date].to_date).to eq(Date.parse("2022-01-28"))
      expect(result[:end_date_context]).to eq("course")
    end

    it "returns previous day if course end is midnight" do
      @course.update conclude_at: Time.zone.parse("2022-01-28T00:00:00")
      result = @course_pace.effective_end_date(with_context: true)
      expect(result[:end_date].to_date).to eq(Date.parse("2022-01-27"))
      expect(result[:end_date_context]).to eq("course")
    end

    it "returns course's term end if available" do
      @course.enrollment_term.update end_at: Time.zone.parse("2022-01-27T13:00:00")
      result = @course_pace.effective_end_date(with_context: true)
      expect(result[:end_date].to_date).to eq(Date.parse("2022-01-27"))
      expect(result[:end_date_context]).to eq("term")
    end

    it "returns nil if no fixed date is available" do
      @course.restrict_enrollments_to_course_dates = false
      @course.enrollment_term.update start_at: nil, end_at: nil
      result = @course_pace.effective_end_date(with_context: true)
      expect(result[:end_date]).to be_nil
      expect(result[:end_date_context]).to eq("hypothetical")
    end
  end
end
