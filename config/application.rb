require File.expand_path('../boot', __FILE__)

require 'rails/all'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module DorFetcherService
  class Application < Rails::Application
    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration should go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded.

    # Set Time.zone default to the specified zone and make Active Record auto-convert to this zone.
    # Run "rake -D time" for a list of tasks for finding time zone names. Default is UTC.
    # config.time_zone = 'Central Time (US & Canada)'

    # The default locale is :en and all translations from config/locales/*.rb,yml are auto loaded.
    # config.i18n.load_path += Dir[Rails.root.join('my', 'locales', '*.{rb,yml}').to_s]
    # config.i18n.default_locale = :de
    
    load_yaml_config = lambda { |yaml_file|
      full_path = File.expand_path(File.join(File.dirname(__FILE__), yaml_file))
      yaml      = YAML.load(File.read full_path)
      return yaml[Rails.env]
    }
    
    config.solr_url=load_yaml_config.call('solr.yml')['url']

    
  end
  
  
end

#Convienence constant for SOLR_URL and SOLR
Solr_URL = DorFetcherService::Application.config.solr_url
Solr= RSolr.connect :url => Solr_URL