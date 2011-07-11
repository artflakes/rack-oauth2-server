module Rack
  module OAuth2
    class Server

      # Access token. This is what clients use to access resources.
      #
      # An access token is a unique code, associated with a client, an identity
      # and scope. It may be revoked, or expire after a certain period.
      class AccessToken
        class << self

          # Creates a new AccessToken for the given client and scope.
          def create_token_for(client, scope)
            scope = Utils.normalize_scope(scope) & client.scope # Only allowed scope
            token = { :id=>Server.secure_random, :scope=>scope.join(","), :client_id=>client.id,
                      :created_at=>Time.now.to_i, :expires_at=>nil, :revoked=>nil }
            collection.insert token
            Client.collection.filter(:id => client.id).update(:tokens_granted => :tokens_granted + 1)
            Server.new_instance self, token
          end

          # Find AccessToken from token. Does not return revoked tokens.
          def from_token(token)
            Server.new_instance self, collection.filter(:id => token, :revoked => nil).first
          end

          # Get an access token (create new one if necessary).
          def get_token_for(identity, client, scope)
            raise ArgumentError, "Identity must be String or Integer" unless String === identity || Integer === identity
            scope = Utils.normalize_scope(scope) & client.scope # Only allowed scope
            unless token = collection.filter(:identity => identity, :scope => scope.join(","), :client_id => client.id, :revoked => nil).first
              token = { :id=>Server.secure_random, :identity=>identity, :scope=>scope.join(","),
                        :client_id=>client.id, :created_at=>Time.now.to_i,
                        :expires_at=>nil, :revoked=>nil }
              collection.insert token
              Client.collection.filter(:id => client.id).update(:tokens_granted => :tokens_granted + 1)
            end
            Server.new_instance self, token
          end

          # Find all AccessTokens for an identity.
          def from_identity(identity)
            collection.filter({ :identity=>identity }).map { |fields| Server.new_instance self, fields }
          end

          # Returns all access tokens for a given client, Use limit and offset
          # to return a subset of tokens, sorted by creation date.
          def for_client(client_id, offset = 0, limit = 100)
            client_id = client_id.to_s
            collection.filter({ :client_id => client_id }).order(:created_at).limit(limit, offset).
              map { |token| Server.new_instance self, token }
          end

          # Returns count of access tokens.
          #
          # @param [Hash] filter Count only a subset of access tokens
          # @option filter [Integer] days Only count that many days (since now)
          # @option filter [Boolean] revoked Only count revoked (true) or non-revoked (false) tokens; count all tokens if nil
          # @option filter [String, ObjectId] client_id Only tokens grant to this client
          def count(filter = {})
            select = {}
            set = collection
            set = set.filter(:client_id => filter[:client_id].to_s) if filter[:client_id]
            if filter[:days]
              now = Time.now.to_i
              set = if filter[:revoked]
                      set.filter(:revoked => (now - filter[:days] * 86400)...now)
                    else
                      set.filter(:created_at => (now - filter[:days] * 86400)...now)
                    end

            elsif filter.has_key?(:revoked)
              set = if filter[:revoked]
                      set.filter(~{:revoked => nil})
                    else
                      set.filter :revoked => nil
                    end
            end
            set.count
          end

          def historical(filter = {})
            days = filter[:days] || 60
#            select = { :$gt=> { :created_at=>Time.now - 86400 * days } }
            select = {}
            set = Server::AccessToken.collection
            set = set.filter :client_id => filter[:client_id].to_s if filter[:client_id]
            set.all
  #          raw = Server::AccessToken.collection.group("function (token) { return { ts: Math.floor(token.created_at / 86400) } }",
 #             select, { :granted=>0 }, "function (token, state) { state.granted++ }")
#            raw.sort { |a, b| a["ts"] - b["ts"] }
          end

          def collection
            Server.database[:access_tokens]
          end
        end

        # Access token. As unique as they come.
        attr_reader :id
        alias :token :id
        # The identity we authorized access to.
        attr_reader :identity
        # Client that was granted this access token.
        attr_reader :client_id
        # The scope granted to this token.
        def scope
          if @scope.kind_of? String
            @scope = @scope.split ","
          else
            @scope || []
          end
        end
        # When token was granted.
        attr_reader :created_at
        # When token expires for good.
        attr_reader :expires_at
        # Timestamp if revoked.
        attr_accessor :revoked
        # Timestamp of last access using this token, rounded up to hour.
        attr_accessor :last_access
        # Timestamp of previous access using this token, rounded up to hour.
        attr_accessor :prev_access

        # Updates the last access timestamp.
        def access!
          today = (Time.now.to_i / 3600) * 3600
          if last_access.nil? || last_access < today
            AccessToken.collection.filter(:id=>token).update(:last_access=>today, :prev_access=>last_access)
            self.last_access = today
          end
        end

        # Revokes this access token.
        def revoke!
          self.revoked = Time.now.to_i
          AccessToken.collection.filter(:id=>token).update(:revoked=>revoked)
          Client.collection.filter(:id=>client_id).update(:tokens_revoked => :tokens_revoked + 1)
        end

      end

    end
  end
end
