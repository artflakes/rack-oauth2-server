require "mongo"
require "sequel"
require "openssl"
require "rack/oauth2/server/errors"
require "rack/oauth2/server/utils"

module Rack
  module OAuth2
    class Server

      class << self
        # A Mongo::DB object.
        attr_accessor :database
        
        # Create new instance of the klass and populate its attributes.
        def new_instance(klass, fields)
          return unless fields
          instance = klass.new
          fields.each do |name, value|
            instance.instance_variable_set :"@#{name}", value
          end
          instance
        end

        # Long, random and hexy.
        def secure_random
          OpenSSL::Random.random_bytes(32).unpack("H*")[0]
        end
        
        # @private
        def create_indexes(&block)
          if block
            @create_indexes ||= []
            @create_indexes << block
          elsif @create_indexes
            @create_indexes.each do |block|
              block.call
            end
            @create_indexes = nil
          end
        end

        def adapter
          raise 'No Adapter configured. You must configure it using Server.adapter = :sequel or :mongodb' unless @adapter
          @adapter
        end

        def adapter= new_adapter
          unless @adapter == new_adapter
            @adapter = new_adapter
            require "rack/oauth2/models/#{new_adapter}"
          end
          @adapter
        end
 
       	def database
      		raise 'No database Configured. You must configure it using Server.database = MongoDB::Connection.new()[db_name] ' unless @database
      		@database
 	 			end	
      end

    end
  end
end


