require 'v1/search_error'
require 'v1/repository'
require 'v1/schema'
require 'v1/searchable/query'
require 'v1/searchable/filter'
require 'v1/searchable/facet'
require 'tire'
require 'active_support/core_ext'

module V1

  module Searchable

    # Default pagination size for search results
    DEFAULT_PAGE_SIZE = 10

    # Default max page size
    DEFAULT_MAX_PAGE_SIZE = 100
    
    # Default sort order for search results
    DEFAULT_SORT_ORDER = 'asc'

    # Maximum facets to return. See use case details
    MAXIMUM_FACETS_COUNT = 'not implemented'

    # General query params that are not type-specific
    BASE_QUERY_PARAMS = %w( q controller action sort_by sort_order page page_size facets fields callback ).freeze
    
    def validate_params(params)
      # Raises exception if any unrecognized search params are present. Extensions made
      # to the mapping for query reasons (e.g: spatial.distance) are added here as well.
      #TODO: Make the mapped_fields call type-specific to avoid overlaps between fields/subfields
      # with the same name across multiple types
      invalid_fields = params.keys - (BASE_QUERY_PARAMS + V1::Schema.mapped_fields)
      if invalid_fields.any?
        raise BadRequestSearchError, "Invalid field(s) specified in query: #{invalid_fields.join(',')}"
      end
    end

    def search(params={})
      validate_params(params)
      searcher = Tire.search(V1::Config::SEARCH_INDEX) do |search|
        #intentional empty search: search.query { all }
        got_queries = true if V1::Searchable::Query.build_all(search, params)
        got_queries = true if V1::Searchable::Filter.build_all(search, params)
        got_queries = true if V1::Searchable::Facet.build_all(search, params['facets'], !got_queries)
        #TODO: for symmetry's sake, make Facet.build_all take params like the others

        sort_attrs = build_sort_attributes(params)
        search.sort { by(*sort_attrs) } if sort_attrs
        
        #canned example to sort by geo_point, unverified
        # sort do
        #   by :_geo_distance, 'addresses.location' => [lng, lat], :unit => 'mi'
        # end
        
        # handle pagination
        search.from get_search_starting_point(params)
        search.size get_search_size(params)

        # fields(['title', 'description'])
        
        # for testability, this block should always return its search object
        search
      end

      #verbose_debug(searcher)
      return build_dictionary_wrapper(searcher)
    end

    def build_sort_attributes(params)
      #TODO big picture check on field being available 
      return nil unless params['sort_by'].present?
 
      order = params['sort_order']
      if !( order.present? && %w(asc desc).include?(order.downcase) )
        order = DEFAULT_SORT_ORDER 
      end

      [params['sort_by'], order]
    end

    def build_dictionary_wrapper(search)
      #BARRETT: should just use search.results instead of json parsing, etc.
      response = JSON.parse(search.response.body) #.to_json
      Rails.logger.info search.response.body.as_json      

      docs = reformat_result_documents(response["hits"]["hits"])

      { 
        'count' => response["hits"]["total"],
        'start' => search.options[:from],
        'limit' => search.options[:size],
        'docs' => docs,
        'facets' => response['facets']
      }
    end

    def reformat_result_documents(docs)
      docs.map { |doc| doc['_source'].merge!({'score' => doc['_score']}) } 
    end

    def get_search_starting_point(params)
      page = params["page"].to_i
      page == 0 ? 0 : get_search_size(params) * (page - 1)
    end

    def get_search_size(params)
      size = params["page_size"].to_i
      if size == 0
        DEFAULT_PAGE_SIZE
      elsif size > DEFAULT_MAX_PAGE_SIZE
        DEFAULT_MAX_PAGE_SIZE
      else
        size
      end
    end

    def fetch(id)
      V1::Repository.fetch(id)
    end

    def verbose_debug(search)
      if search.to_json == '{}'
        puts "********* WARNING ********* "
        puts "* Running a completely empty query. Probably not what you intended. *"
        puts "*************************** "
      end
      puts "CURL: #{search.to_curl}"
      puts "JSON: #{search.to_json}"

      search.results.each do |result|
        puts "### HIT (#{result['_id']}): #{result.inspect}"
      end
    end

    def direct(params={})
      s = Tire.search(V1::Config::SEARCH_INDEX) do
        query do
          boolean do
            must { string 'perplexed' }
          end
        end
      end
      verbose_debug(s)
      s.results
    end
    
  end

end
