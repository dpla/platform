require 'v1/standard_dataset'
require 'json'
require 'couchrest'

module V1

  module Repository

    # Accepts an array of id strings ["A,"1","item1"], a single string id "1"
    # Or a comma separated string of ids "1,2,3"
    def self.fetch(id_list)
      db = CouchRest.database(read_only_endpoint)
      id_list = id_list.split(',') if id_list.is_a?(String)
      db.get_bulk(id_list)["rows"] 
    end

    def self.read_only_endpoint
      @endpoint_uri ||= V1::Config.get_repository_read_only_endpoint + '/' + repository_database
    end

    def self.admin_endpoint
      @endpoint_uri ||= V1::Config.get_repository_admin_endpoint + '/' + repository_database
    end

    def self.repository_database
      V1::Config::REPOSITORY_DATABASE
    end

    def self.repository_admin_endpoint
      V1::Config.get_repository_admin_endpoint
    end

    def self.recreate_database!
      # Delete and create the database
      #TODO: add production env check

      # delete it if it exists
      CouchRest.database(admin_endpoint).delete! rescue RestClient::ResourceNotFound

      # create a new one
      db = CouchRest.database!(admin_endpoint)

      # create read only user and lock down security
      create_read_only_user
      lock_down_repository_roles

      V1::StandardDataset.recreate_river!

      items = process_input_file("../standard_dataset/items.json")
      db.bulk_save items
    end

    def self.create_read_only_user
      username = V1::Config.get_repository_read_only_username
      password = V1::Config.get_repository_read_only_password

      # delete read only user if it exists
      users_db = CouchRest.database("#{repository_admin_endpoint}/_users")
      read_only_user = users_db.get("org.couchdb.user:#{username}") rescue RestClient::ResourceNotFound
      users_db.delete_doc(read_only_user) if read_only_user.is_a? CouchRest::Document

      user_hash = {
        :type => "user",
        :name => username,
        :password => password,
        :roles => ["reader"]
      }

      RestClient.put(
        "#{repository_admin_endpoint}/_users/org.couchdb.user:#{username}",
        user_hash.to_json,
        {:content_type => :json, :accept => :json}
      )
    end

    def self.lock_down_repository_roles
      security_hash = {
        :admins => {"roles" => ["admin"]},
        :readers => {"roles"  => ["admin","reader"]}
      }
      RestClient.put(
        "#{repository_admin_endpoint}/#{repository_database}/_security",
        security_hash.to_json
      )

      # add validation to ensure only admin can create new docs
      design_doc_hash = {
        :_id => "_design/auth",
        :language => "javascript",
        :validate_doc_update => "function(newDoc, oldDoc, userCtx) { if (userCtx.roles.indexOf('_admin') !== -1) { return; } else { throw({forbidden: 'Only admins may edit the database'}); } }"
      }
      RestClient.put(
        "#{repository_admin_endpoint}/#{repository_database}/_design/auth",
        design_doc_hash.to_json
      )
    end

    def self.process_input_file(json_file)
      items_file = File.expand_path(json_file, __FILE__)
      JSON.load( File.read(items_file) )
    end

  end

end