# frozen_string_literal: true

require 'active_support/inflector'

# A mixin module that is part of application controller, this provides base functionality to all classes
module Fetcher
  @@field_return_list = [ID_FIELD, LAST_CHANGED_FIELD, TYPE_FIELD, TITLE_FIELD, TITLE_FIELD_ALT, CATKEY_FIELD]

  # Run a solr query, and do some logging
  # @param params [Hash] params to send to solr
  # @param method [String] type of query to send to solr (defaults to "select")
  # @return [Hash] solr response
  # @example
  #   response=run_solr_query(:q => 'dude')
  def run_solr_query(params, method = 'select')
    start_time = Time.zone.now
    response = SOLR.get method, params: params
    elapsed_time = Time.zone.now - start_time
    Rails.logger.info "Request from #{request.remote_ip} to #{request.fullpath} at #{Time.zone.now}"
    Rails.logger.info "Solr query: #{params}"
    Rails.logger.info "Query run time: #{elapsed_time.round(3)} seconds (#{(elapsed_time / 60.0).round(2)} minutes)"
    response
  end

  # Given the user's querystring parameters, and a fedora type, return a solr response containing all of the objects associated with that type (potentially limited by rows or date if specified by the user)
  # @param params [Hash] querystring parameters from user, which could be an empty hash
  # @param ftype [String] fedora object type, could be :apo or :collection
  # @return [Hash] solr response
  # @example
  #   find_all_fedora_type(params, :apo)
  def find_all_fedora_type(params, ftype)
    # ftype should be :collection or :apo (or other symbol if we added more since this was updated)
    date_range_q = get_date_solr_query(params)
    solrparams = { q: "#{TYPE_FIELD}:\"#{FEDORA_TYPES[ftype]}\" #{date_range_q}", wt: :json, fl: @@field_return_list.join(',') }
    get_rows(solrparams, params)
    response = run_solr_query(solrparams)
    determine_proper_response(params, response)
  end

  # Given the user's querystring parameters (including the ID paramater, which represents the druid), and a fedora object type, return a solr response containing all of the objects controlled by that druid of that type (potentially limited by rows or date if specified by the user)
  # @param params [Hash] querystring parameters from user, which must include :id of the druid
  # @param controlled_by [String] fedora object type, could be :apo or :collection
  # @return [Hash] solr response containing all of the matching objects controlled by the :id
  # @example
  #   find_all_under(params, :apo)
  def find_all_under(params, controlled_by)
    # controlled_by should be :collection or :apo (or other symbol if we added more since this was updated)
    date_range_q = get_date_solr_query(params)
    solrparams = {
      q: "(#{CONTROLLER_TYPES[controlled_by]}:\"#{druid_of_controller(params[:id])}\" OR #{ID_FIELD}:\"#{druid_for_solr(params[:id])}\") #{date_range_q}",
      wt: :json,
      fl: @@field_return_list.join(',')
    }
    get_rows(solrparams, params)
    response = run_solr_query(solrparams)
    # @TODO: If APO in response and said APO's druid != user provided druid, recursion!
    determine_proper_response(params, response)
  end

  # Given the user's querystring parameters (including the ID paramater, which represents the tag), return a solr response containing all of the objects associated with the supplied tag(potentially limited by rows or date if specified by the user)
  # @param params [Hash] querystring parameters from user, which must include :id of the tag
  # @return [Hash] solr response
  # @example
  #   find_in_solr(params)
  def find_in_solr(params)
    date_range_q = get_date_solr_query(params)
    solrparams = {
      q: "(#{CONTROLLER_TYPES[:tag]}:\"#{params[:id]}\") #{date_range_q}",
      wt: :json,
      fl: @@field_return_list.join(',')
    }
    get_rows(solrparams, params)
    response = run_solr_query(solrparams)
    determine_proper_response(params, response)
  end

  # Given a druid without the druid prefix (e.g. oo000oo0001), add the prefixes needed for querying solr for controllers
  # @param druid [String] druid
  # @return [String] druid, fully prefixed
  # @example
  #   druid_for_controller('oo000oo0001') # returns info:fedora/druid:oo000oo0001
  def druid_of_controller(druid)
    FEDORA_PREFIX + DRUID_PREFIX + parse_druid(druid)
  end

  # Given a druid without the druid prefix (e.g. oo000oo0001), add the prefix needed for querying solr
  # @param druid [String] druid
  # @return [String] druid, including 'druid:' prefix
  # @example
  #   druid_for_solr('oo000oo0001') # returns druid:oo000oo0001
  def druid_for_solr(druid)
    DRUID_PREFIX + parse_druid(druid)
  end

  # Given a druid in any format (e.g. oo000oo0001 or druid:oo00oo0001), returns only the distinct part, stripping the "druid:" prefix
  # @param druid [String] possible druid
  # @return [String] druid, without 'druid:' or other prefix
  # @raise if invalid druid passed
  # @example
  #   parse_druid('oo000oo0001')       # returns oo000oo0001
  #   parse_druid('druid:oo000oo0001') # returns oo000oo0001
  #   parse_druid('junk') # throws an exception
  def parse_druid(druid)
    matches = druid.match(/[a-zA-Z]{2}\d{3}[a-zA-Z]{2}\d{4}/)
    matches.nil? ? raise('invalid druid') : matches[0]
  end

  # Given a hash containing "first_modified" and "last_modified", ensures the date formats are valid, converts to proper ISO8601 if they are.
  # If first_modified is missing, sets to the earliest possible date.
  # If last_modified is missing, sets to current date/time.
  # If invalid dates are passed in, throws an exception.
  #
  # @param p [Hash] which includes :first_modified and :last_modified keys as coming in from the querystring from the user
  # @return [Hash{Symbol => String}] containing :first and :last keys with iso8601 datetime strings
  # @example
  #   get_times(:first_modified=>'01/01/2014') # returns {:first=>'2014-01-01T00:00:00Z',last:'CURRENT_DATETIME_IN_UTC_ISO8601'}
  #   get_times(:first_modified=>'junk') # throws exception
  #   get_times(:first_modified=>'01/01/2014',:last_modified=>'01/01/2015') # returns {:first=>'2014-01-01T00:00:00Z',last:'2015-01-01T00:00:00Z'}
  def get_times(params)
    # default value set here rather than in prior line to handle explicit `nil` passed to method
    params ||= {}
    first_modified = params[:first_modified] || Time.zone.at(0).iso8601
    last_modified  = params[:last_modified]  || latest_date
    begin
      first_modified_time = Time.zone.parse(first_modified).iso8601
      last_modified_time  = Time.zone.parse(last_modified).iso8601
    rescue StandardError
      raise 'invalid time paramaters'
    end
    raise 'start time is before end time' if first_modified_time >= last_modified_time

    { first: first_modified_time, last: last_modified_time }
  end

  # Given a hash containing "first_modified" and "last_modified", returns the solr query part to append to the overall query to properly return dates, which my be blank if user asks for just registered objects
  # @param p [Hash] which includes :first_modified and :last_modified keys as coming in from the querystring from the user
  # @return [String] solr query part
  # @example
  #   get_date_solr_query(:first_modified=>'01/01/2014') # returns "and published_dttsim:["2014-01-01T00:00:00Z" TO "CURRENT_DATETIME"]"
  #   get_date_solr_query(:first_modified=>'01/01/2014',:status=>'registered') # returns ""
  def get_date_solr_query(params = {})
    times = get_times(params)
    registered_only?(params) ? '' : "AND #{LAST_CHANGED_FIELD}:[\"#{times[:first]}\" TO \"#{times[:last]}\"]" # unless the user has asked for only registered items, apply the date range for published date
  end

  # Given a params hash that will be passed to solr, adds in the proper :rows value depending on if we are requesting a certain number of rows or not
  # @param solrparams [Hash] solr params has to be altered
  # @param params [Hash] query string params from user
  # @return [Hash] solr params hash
  def get_rows(solrparams, params)
    params.key?(:rows) ? solrparams.merge!(rows: params[:rows]) : solrparams.merge!(rows: 100_000_000) # if user passes in the rows they want, use that, else just return everything
  end

  # Given a params hash from the user, tells us if they only want registered items (ignoring accessioning and date ranges)
  # @param params [Hash] query string params from user
  # @return [Boolean] true if user wants registered items only
  def registered_only?(params)
    (params && params[:status] && params[:status].downcase) == 'registered'
  end

  # Given a solr response hash, create a json string to properly return the data.
  # @param params [Hash] query string params from user
  # @param response [Hash] solr response
  # @return [Hash] formatted for delivery as JSON
  def format_json(params, response)
    all_json = {}
    times = get_times(params)

    # Create A Hash that contains an empty list for each Fedora Type
    FEDORA_TYPES.each do |_key, value|
      all_json.store(value.pluralize.to_sym, [])
    end

    response['response']['docs'].each do |doc|
      # First determine type of this specific druid
      @@field_return_list.each { |f| doc[f] ||= [] }
      type   = doc[TYPE_FIELD].first || 'unknown_type'
      title1 = doc[TITLE_FIELD].first
      title2 = doc[TITLE_FIELD_ALT]
      title = ''
      title = title1 if title1.present?
      title = title2 if title2.present?
      j = { druid: doc[ID_FIELD], latest_change: determine_latest_date(times, doc[LAST_CHANGED_FIELD]), title: title }
      j[:catkey] = doc[CATKEY_FIELD].first unless doc[CATKEY_FIELD].nil?
      all_json[type.downcase.pluralize.to_sym] << j # Append this little json stub to its proper parent array
    end

    # Now we need to delete any nil arrays and sum the ones that aren't nil
    total_count = 0
    a = {}
    all_json.each do |key, value|
      if value.size.zero?
        all_json.delete(key)
      else
        a[key] = value.size
        total_count += value.size
      end
    end
    a[:total_count] = total_count
    all_json.store(:counts, a)
    all_json
  end

  # Determines if the user asked for just a count of the item or a full druid list for the item and returns accordingly
  # @param params [Hash] query string params from user
  # @option params [Integer] :rows 0 indicates count-only request
  # @param response [Hash] solr response
  # @return [Hash] properly formatted json
  def determine_proper_response(params, response)
    raise ArgumentError, 'Empty response from Solr?' if response.nil? || response['response'].nil?
    return response['response']['numFound'] if params[:rows] == '0'

    response['response']['docs'] ||= []
    format_json(params, response)
  end

  # Determine the latest date modified/changed, optionally within a given timeframe.
  # If no timeframe provided, it is just the latest date.
  #
  # @param times [Hash] properly formatted :first and/or :last dates
  # @param last_changed [array] change dates from solr response
  # @return [String] latest modified/changed date
  #
  def determine_latest_date(times, last_changed)
    # Sort with latest date first
    return nil unless last_changed&.size&.positive?

    last_changed.sort.reverse_each do |c|
      # all changes_sorted have to be equal or greater than times[:first], otherwise Solr would have had
      # zero results for this, we just want the first one earlier than :last
      return c if c <= times[:last] && c >= times[:first]
    end
    # If we get down here we have a big problem, because there should have been at least one date earlier than times[:last]
    raise('Error finding latest changed date, failed to find one')
  end

  def latest_date
    '9999-12-31T23:59:59Z'
  end
end
