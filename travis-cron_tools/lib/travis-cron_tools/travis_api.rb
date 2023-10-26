require "json"
require "net/http"
require "uri"

module Travis
  module CronTools
    class TravisAPI
      attr_reader :organization, :repo

      class TravisError < RuntimeError
      end

      def initialize(organization, repo, auth_token = :from_env)
        auth_token = if auth_token == :from_env
                        ENV["TRAVIS_TOKEN"]
                      else
                        auth_token
                      end

        @organization = organization
        @repo = repo
        @base_url = "https://api.travis-ci.org/repo/#{@organization}%2F#{@repo}"

        @headers = {
           "Content-Type" =>  "application/json",
           "Accept" => "application/json",
           "Travis-API-Version" => "3",
           "Authorization" => "token #{auth_token}"
        }
      end

      # Lazily fetches all builds.
      def builds(filters = {})
        fetch_resources_lazily("builds", filters)
      end

      def create_request(request_options)
        uri = URI.parse("#{@base_url}/requests")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        request = Net::HTTP::Post.new(uri.request_uri, @headers)
        request.body = JSON.dump(request: request_options)
        response = http.request(request)
        json = JSON.load response.body

        if response.code != "202"
          raise TravisError.new("Travis API error #{response.code}: #{json.inspect}")
        end

        json
      end

      private

      def fetch_resources_lazily(resource, filters = {})
        start_url = "#{@base_url}/#{resource}"
        if filters.any?
          start_url += "?"
        end

        start_url += filters.map {|filter_name, filter_value| filter_name.to_s + "=" + filter_value.to_s}.join("&")

        uri = URI.parse(start_url)

        Enumerator.new do |yielder|
          loop do
            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = true
            request = Net::HTTP::Get.new(uri.request_uri, @headers)
            response = http.request(request)

            if response.code != "200"
              raise TravisError.new("Could not perform request; got #{response.code} code! (body: #{(request.body rescue nil).inspect})")
            end

            json = JSON.load response.body

            json["builds"].each do |build|
              yielder << build
            end

            next_url = json["@pagination"]["next"]
            break if next_url.nil?

            # the URL given by the API is relative. Past the domain in front of it.
            uri = URI.parse("https://api.travis-ci.org#{next_url["@href"]}")
          end
        end.lazy
      end
    end
  end
end
