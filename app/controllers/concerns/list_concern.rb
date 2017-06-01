module ListConcern
  include Redmine::Pagination
  extend ActiveSupport::Concern

  private
  def init_sort(query = @query)
    sort_init query.sort_criteria.empty? ? [%w(date asc)] : query.sort_criteria
    sort_update query.sortable_columns
    query.sort_criteria = @sort_criteria.to_a
  end

  def list_arguments(query = @query, options = {})
    list_arguments = {query: query, action_name: action_name, sort_criteria: @sort_criteria}
    if query.valid?
      scope = query.results_scope order: sort_clause
      count = scope.count
      paginator = Paginator.new count, options[:per_page] || per_page_option, params[options[:page_param] || :page], options[:page_param]
      entries = scope.offset(paginator.offset).limit(paginator.per_page)
      list_arguments.merge! count: count, paginator: paginator, entries: entries
    end
    list_arguments
  end
end
