module Hourglass
  class AlreadyBookedException < StandardError
  end

  class TimeLog < ActiveRecord::Base
    include Namespace

    belongs_to :user
    has_one :time_booking, dependent: :destroy
    has_one :time_entry, through: :time_booking

    after_initialize :init

    validates_presence_of :user, :start, :stop
    validates_length_of :comments, maximum: 255, allow_blank: true
    validate :stop_is_valid
    validate :does_not_overlap_with_other, if: [:user, :start?, :stop?]

    scope :booked_on_project, lambda { |project_id|
      joins(:time_entry).where(time_entries: {project_id: project_id})
    }
    scope :with_start_in_interval, lambda { |floor, ceiling|
      where(arel_table[:start].gt(floor).and(arel_table[:start].lt(ceiling)))
    }

    scope :overlaps_with, lambda { |start, stop|
      where(arel_table[:start].lt(stop).and(arel_table[:stop].gt(start)))
    }

    def init
      self.start = start.change(sec: 0) if start
      self.stop = stop.change(sec: 0) if stop
    end

    def build_time_booking(args = {})
      super time_booking_arguments default_booking_arguments.merge args
    end

    def update(attributes)
      round = attributes.delete :round
      ActiveRecord::Base.transaction do
        result = super attributes
        if booked?
          DateTimeCalculations.booking_process user, start: start, stop: stop, project_id: time_booking.project_id, round: round do |options|
            time_booking.update start: options[:start], stop: options[:stop], time_entry_attributes: {hours: DateTimeCalculations.time_diff_in_hours(options[:start], options[:stop])}
            time_booking
          end
          raise ActiveRecord::Rollback unless time_booking.persisted?
        end
        result
      end
    end

    def book(attributes)
      raise AlreadyBookedException if booked?
      DateTimeCalculations.booking_process user, default_booking_arguments.merge(attributes.except(:start, :stop)) do |options|
        create_time_booking time_booking_arguments options
      end
    end

    def split(args)
      split_at = args[:split_at].change(sec: 0)
      insert_new_before, round = args.values_at :insert_new_before, :round
      return if start >= split_at || split_at >= stop
      old_time = insert_new_before ? start : stop
      ActiveRecord::Base.transaction do
        update insert_new_before ? {start: split_at, round: round} : {stop: split_at, round: round}
        new_time_log_args = insert_new_before ? {start: old_time, stop: split_at} : {start: split_at, stop: old_time}
        self.class.create new_time_log_args.merge user: user, comments: comments
      end
    end

    def combine_with(time_log)
      return false if stop != time_log.start || booked? || time_log.booked?
      new_stop = time_log.stop
      ActiveRecord::Base.transaction do
        time_log.destroy
        update stop: new_stop
      end
      true
    end

    def hours
      DateTimeCalculations.time_diff_in_hours start, stop
    end

    def booked?
      time_booking.present? && time_booking.persisted?
    end

    def bookable?
      !booked?
    end

    def to_json(args = {})
      super args.deep_merge methods: :hours
    end

    private
    def default_booking_arguments
      {start: start, stop: stop, comments: comments, time_log_id: id, user: user}.with_indifferent_access
    end

    def time_booking_arguments(options)
      options
          .slice(:start, :stop, :time_log_id)
          .merge time_entry_attributes: time_entry_arguments(options)
    end

    def time_entry_arguments(options)
      options
          .slice(:project_id, :issue_id, :comments, :activity_id, :user)
          .merge spent_on: User.current.time_to_date(options[:start]), hours: DateTimeCalculations.time_diff_in_hours(options[:start], options[:stop])
    end

    def stop_is_valid
      errors.add :stop, :invalid if stop.present? && start.present? && stop <= start
    end

    def does_not_overlap_with_other
      overlapping_time_logs = user.hourglass_time_logs.where.not(id: id).overlaps_with start, stop
      errors.add :base, :overlaps unless overlapping_time_logs.empty?
    end
  end
end
