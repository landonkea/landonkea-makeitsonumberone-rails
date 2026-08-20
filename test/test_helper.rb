ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

# WebMock replaces Ruby's real HTTP layer during tests, so any test that
# forgets to stub a request gets a loud failure instead of accidentally
# making a real network call (and, for this app specifically, instead of
# accidentally spending real Anthropic API credits every time we run the
# suite).
require "webmock/minitest"
WebMock.disable_net_connect!(allow_localhost: true)

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
