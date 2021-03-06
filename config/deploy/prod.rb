# frozen_string_literal: true

set :bundle_without, %w[deployment test development].join(' ')
server 'dorfetcher-prod.stanford.edu', user: 'lyberadmin', roles: %w[web db app]

Capistrano::OneTimeKey.generate_one_time_key!
set :rails_env, 'production'
