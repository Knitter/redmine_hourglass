class HourglassCompletionController < Hourglass::ApiBaseController
  include Hourglass::ApplicationHelper

  accept_api_auth :issues, :activities

  def issues
    issue_arel = Issue.arel_table
    issues = Issue.visible.joins(:project).where(Project.allowed_to_one_of_condition User.current, Hourglass::AccessControl.permissions_from_action(controller: 'hourglass/time_logs', action: 'book')).where(
        issue_arel[:id].eq(params[:term].to_i)
            .or(issue_arel[:id].matches("%#{params[:term]}%"))
            .or(issue_arel[:subject].matches("%#{params[:term]}%"))
    )
    issue_list = issues.map do |issue|
      {
          label: "##{issue.id} #{issue.subject}",
          issue_id: "#{issue.id}",
          project_id: issue.project.id}
    end
    respond_with_success issue_list
  end

  def activities
    activities = activity_collection User.current.projects.find_by id: params[:project_id]
    activities_list = activities.map do |activity|
      {
          id: activity.id,
          name: activity.name
      }
    end
    respond_with_success activities_list
  end
end
