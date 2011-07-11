require "bundler"
Bundler.setup
require "test/unit"
require "rack/test"
require "shoulda"
require "timecop"
require "ap"
require "json"
require "logger"
$: << File.dirname(__FILE__) + "/../lib"
$: << File.expand_path(File.dirname(__FILE__) + "/..")
require "rack/oauth2/server"
require "rack/oauth2/server/admin"


ENV["RACK_ENV"] = "test"
ENV["DATABASE_BACKEND"] ||= "mongodb"
DATABASE = case ENV["DATABASE_BACKEND"].to_sym
           when :mongodb
             Mongo::Connection.new["test"]
           when :sequel
             db = Sequel.sqlite
             db.create_table :auth_requests do
               primary_key :internal_id

               String :id
               String :client_id
               String :scope
               String :redirect_uri
               String :response_type
               String :state
               String :grant_code
               String :access_token
               Integer :authorized_at
               Integer :created_at
               Integer :revoked

               index :client_id
             end

             db.create_table :access_tokens do
               primary_key :internal_id

               String :id
               String :identity
               String :client_id
               String :scope
               String :redirect_uri
               String :response_type
               String :state
               String :grant_code
               Integer :expires_at
               Integer :created_at
               Integer :revoked
               Integer :prev_access
               Integer :last_access

               index :client_id
               index :identity
             end

             db.create_table :access_grants do
               primary_key :internal_id

               String :id
               String :identity
               String :client_id
               String :scope
               String :redirect_uri
               String :response_type
               String :state
               String :grant_code
               String :access_token
               Integer :granted_at
               Integer :expires_at
               Integer :created_at
               Integer :revoked
               Integer :prev_access
               Integer :last_access

               index :client_id
               index :identity
             end

             db.create_table :clients do
               primary_key :internal_id

               String :id

               String :identity
               String :secret
               column :notes, :text
               String :scope
               String :display_name
               String :image_url
               String :link
               String :redirect_uri
               Integer :created_at
               Integer :revoked
               Integer :tokens_granted
               Integer :tokens_revoked

               index :display_name
               index :link
             end
             db
           end

FRAMEWORK = ENV["FRAMEWORK"] || "sinatra"


$logger = Logger.new("test.log")
$logger.level = Logger::DEBUG
Rack::OAuth2::Server::Admin.configure do |config|
  config.set :logger, $logger
  config.set :logging, true
  config.set :raise_errors, true
  config.set :dump_errors, true
  config.oauth.logger = $logger
end


case FRAMEWORK
when "sinatra", nil

  require "sinatra/base"
  puts "Testing with Sinatra #{Sinatra::VERSION}"
  require File.dirname(__FILE__) + "/sinatra/my_app"
  MyApp.oauth.logger = $logger

  class Test::Unit::TestCase
    def app
      Rack::Builder.new do
        map("/oauth/admin") { run Server::Admin }
        map("/") { run MyApp }
      end
    end

    def config
      MyApp.oauth
    end
  end

when "rails"

  RAILS_ENV = "test"
  RAILS_ROOT = File.dirname(__FILE__) + "/rails3"
  begin
    require "rails"
  rescue LoadError
  end

  if defined?(Rails::Railtie)
    # Rails 3.x
    require "rack/oauth2/server/railtie"
    require File.dirname(__FILE__) + "/rails3/config/environment"
    puts "Testing with Rails #{Rails.version}"

    class Test::Unit::TestCase
      def app
        ::Rails.application
      end

      def config
        ::Rails.configuration.oauth
      end
    end

  else
    # Rails 2.x
    RAILS_ROOT = File.dirname(__FILE__) + "/rails2"
    require "initializer"
    require "action_controller"
    require File.dirname(__FILE__) + "/rails2/config/environment"
    puts "Testing with Rails #{Rails.version}"

    class Test::Unit::TestCase
      def app
        ActionController::Dispatcher.new
      end

      def config
        ::Rails.configuration.oauth
      end
    end
  end

else
  puts "Unknown framework #{FRAMEWORK}"
  exit -1
end


class Test::Unit::TestCase
  include Rack::Test::Methods
  include Rack::OAuth2

  def setup
    Server.adapter = ENV["DATABASE_BACKEND"].to_sym
    Server.database = DATABASE
    Server::Admin.scope = %{read write}
    @client = Server.register(:display_name=>"UberClient", :redirect_uri=>"http://uberclient.dot/callback", :scope=>%w{read write oauth-admin})
  end

  attr_reader :client, :end_user

  def teardown
    case ENV["DATABASE_BACKEND"].to_sym
    when :mongodb
      Server::Client.collection.drop
      Server::AuthRequest.collection.drop
      Server::AccessGrant.collection.drop
      Server::AccessToken.collection.drop
    when :sequel
      Server::Client.collection.delete
      Server::AuthRequest.collection.delete
      Server::AccessGrant.collection.delete
      Server::AccessToken.collection.delete
    end
  end
end
