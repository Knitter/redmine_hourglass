module Chronos::QueryBase
  extend ActiveSupport::Concern

  included do
    def initialize(attributes = nil, *args)
      super attributes
      self.filters ||= {}
    end

    def is_private?
      visibility == Query::VISIBILITY_PRIVATE
    end

    def is_public?
      !is_private?
    end

    def results_scope(options = {})
      order_option = [group_by_sort_order, options[:order]].flatten.reject(&:blank?)
      base_scope.
          order(order_option).
          joins(joins_for_order_statement(order_option.join(',')))
    end

    def count_by_group
      grouped_query do |scope|
        scope.count
      end
    end

    private
    def add_users_filter
      users = principals.select { |p| p.is_a?(User) }
      users_values = []
      users_values << ["<< #{l(:label_me)} >>", 'me'] if User.current.logged?
      users_values += users.collect { |s| [s.name, s.id.to_s] }
      add_available_filter 'user_id', type: :list, values: users_values if users_values.any?
    end

    def add_projects_filter
      project_values = []
      if User.current.logged? && User.current.memberships.any?
        project_values << ["<< #{l(:label_my_projects).downcase} >>", 'mine']
      end
      project_values += all_projects_values
      add_available_filter 'project_id', type: :list, values: project_values if project_values.any?
    end

    def add_sub_projects_filter
      sub_projects = project.descendants.visible.to_a
      sub_project_values = sub_projects.collect { |s| [s.name, s.id.to_s] }
      add_available_filter 'subproject_id', type: :list_subprojects, values: sub_project_values if sub_project_values.any?
    end

    def add_issues_filter
      issues = Issue.visible.all
      issue_values = issues.collect { |s| [s.subject, s.id.to_s] }
      add_available_filter 'issue', type: :list, values: issue_values if issue_values.any?
      add_available_filter 'issue_subject', type: :text if issues.any?
    end

    def add_activities_filter
      activities = project ? project.activities : TimeEntryActivity.shared
      activities_values = activities.map { |a| [a.name, a.id.to_s] }
      add_available_filter 'activity_id', type: :list, values: activities_values if activities_values.any?
    end

    def principals
      principals = []
      if project
        principals += project.principals.visible.sort
        unless project.leaf?
          subprojects = project.descendants.visible.to_a
          principals += Principal.member_of(subprojects).visible
        end
      else
        if all_projects.any?
          principals += Principal.member_of(all_projects).visible
        end
      end
      principals.uniq!
      principals.sort!
    end
  end
end