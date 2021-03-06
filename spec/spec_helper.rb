# frozen_string_literal: true

require 'vcr'
require 'coveralls'
Coveralls.wear!('rails')

SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter.new([
                                                                 SimpleCov::Formatter::HTMLFormatter,
                                                                 Coveralls::SimpleCov::Formatter
                                                               ])

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    # This option will default to `true` in RSpec 4. It makes the `description`
    # and `failure_message` of custom matchers include text for helper methods
    # defined using `chain`, e.g.:
    # be_bigger_than(2).and_smaller_than(4).description
    #   # => "be bigger than 2 and smaller than 4"
    # ...rather than:
    #   # => "be bigger than 2"
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  # rspec-mocks config goes here. You can use an alternate test double
  # library (such as bogus or mocha) by changing the `mock_with` option here.
  config.mock_with :rspec do |mocks|
    # Prevents you from mocking or stubbing a method that does not exist on a real object.
    # This is generally recommended, and will default to `true` in RSpec 4.
    mocks.verify_partial_doubles = true
  end
end

# To record new cassettes:
#   remove old ones; update index or configure new source; uncomment default_cassette_options; and run tests
VCR.configure do |c|
  # c.default_cassette_options = { :record => :new_episodes }
  c.cassette_library_dir = 'spec/vcr_cassettes'
  c.hook_into :webmock
end

# Matches if druids and ONLY those druids are in the response
# @param [Array<String>] druids list of druids expected
# @param [Object] response query response body
# @return [void]
def result_should_contain_druids(druids, response)
  expect(response).to be_an Array
  expect(response.size).to eq(druids.size)
  expect(response.map { |d| d['druid'] }).to contain_exactly(*druids)
end

# @see #result_should_contain_druids for params and return
def result_should_not_contain_druids(druids, response)
  expect(response).to be_an Array
  druids.each { |d| expect(response).not_to include(a_hash_including('druid' => d)) }
end

def all_counts_keys
  # do not include counts_key, it is the parent
  [collections_key, items_key, apos_key, total_count_key]
end

def collections_key
  'collections'
end

def items_key
  'items'
end

def apos_key
  'adminpolicies'
end

def counts_key
  'counts'
end

def total_count_key
  'total_count'
end

# Automatically gets total counts, don't need to add it
def verify_counts_section(response, counts)
  total_count = 0
  nil_keys = all_counts_keys - [total_count_key]
  counts.each do |key, value|
    # Make the count is what we expect it to be
    expect(response[counts_key][key]).to eq(value)
    # Go back to the JSON section that lists all the druids and make sure its size equals the value listed in count
    expect(response[key].size).to eq(value)
    total_count += value
    nil_keys -= [key] # key was present, so we don't expect it to be nil
  end
  # If the tester didn't specify total count above, check it
  expect(total_count).to eq(response[counts_key][total_count_key]) if counts[total_count_key].nil?

  # Make sure the keys we expect to be nil aren't in the counts section
  nil_keys.each do |key|
    expect(response[counts_key]).not_to include(key)
  end
end

def just_count_param
  { 'rows' => 0 }
end

def last_mod_test_date_collections
  '2013-12-31T23:59:59Z'
end

def first_mod_test_date_collections
  '2014-1-1T00:00:00Z'
end

def mod_test_date_apos
  '2013-03-13T12:13:14Z'
end

def first_mod_test_date_apos
  '2014-03-13T12:13:14Z'
end
