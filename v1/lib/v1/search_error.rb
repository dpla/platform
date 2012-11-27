module V1

  class SearchError < StandardError
    attr_reader :http_code

    def initialize(msg=nil)
      @msg = msg if msg
    end

    def to_s
      "#{ @msg || self.class }"
    end

  end

  class BadRequestSearchError < SearchError
    def initialize(msg=nil)
      super
      @http_code = 400
    end
  end

  class UnauthorizedSearchError < SearchError
    def initialize(msg=nil)
      super
      @http_code = 401
    end
  end

  class RateLimitExceededSearchError < SearchError
    def initialize(msg=nil)
      super
      @http_code = 403
    end
  end

  class NotFoundSearchError < SearchError
    def initialize(msg=nil)
      super
      @http_code = 404
    end
  end

  class NotAcceptableSearchError < SearchError
    def initialize(msg=nil)
      super
      @http_code = 406
    end
  end


  class InternalServerSearchError < SearchError
    def initialize(msg=nil)
      super
      @http_code = 500
    end
  end

  class ServiceUnavailableSearchError < SearchError
    def initialize(msg=nil)
      super
      @http_code = 503
    end
  end

end
