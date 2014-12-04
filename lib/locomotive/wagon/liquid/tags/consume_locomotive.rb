module Locomotive
  module Wagon
    module Liquid
        module Tags
        # Extends the `consume` tag to make Locomotive syndication easier
        # to perform
        #
        # Serves as a Locomotive API proxy, handling things like basic auth, base URLs,
        # and query string building
        #
        # Recognizes the following API endpoints:
        #
        # * "events"
        # * "people"
        #
        # Usage:
        #
        # {% consume_locomotive events from 'events' city: 'Seattle', since: '2014-01-01' %}
        #   {% for event in events %}
        #   {% endfor %}
        # {% endconsume_locomotive %}
        class ConsumeLocomotive < Consume

          Syntax = /(#{::Liquid::VariableSignature}+)\s*from\s*(#{::Liquid::QuotedString}|#{::Liquid::VariableSignature}+)\s*,\s*(#{::Liquid::QuotedString}|#{::Liquid::VariableSignature}+)/

          def initialize(tag_name, markup, tokens, context)
            if markup =~ Syntax
              @locomotive_api_key = ENV['LOCOMOTIVE_API_KEY'] || ''
              prepare_base($3)
            end
            super
          end

          def prepare_options(markup)
            @options ||= {}
            @options[:query] ||= {}
            markup.scan(::Liquid::TagAttributes) do |key, value|
              if key == "query"
                CGI.parse(value.gsub(/['"]/, '')).each do |key, value|
                  @options[:query][key.to_sym] = value.first
                end
              else
                @options[key] = value if key != 'http'
              end
            end

            @options['timeout'] = @options['timeout'].to_f if @options['timeout']
            @expires_in = (@options.delete('expires_in') || 0).to_i
          end

          def render context
            if instance_variable_defined? :@base_url_variable_name
              @locomotive_url = context[@base_url_variable_name]
            end
            if instance_variable_defined? :@variable_name
              @url = context[@variable_name]
            end

            render_all_without_cache(context)
          end

          def prepare_base token
            if token.match(::Liquid::QuotedString)
              @locomotive_url = token.gsub(/['"]/, '')
            elsif token.match(::Liquid::VariableSignature)
              @base_url_variable_name = token
            else
              raise ::Liquid::SyntaxError.new("Syntax Error in 'consume_locomotive' - Valid syntax: consume <var> from \"<url>\", \"<base>\" [username: value, password: value]")
            end
          end

          def render_url
            # Drop leading slash if present
            rendered_url = @url.slice(1, @url.length) if @url[0] == "/"

            # Set up auth_token
            @options[:query][:auth_token] ||= locomotive_auth_token

            # Prepend value and wrap in quotes before passing along
            "http://#{ @locomotive_url }/locomotive/api/#{ @url }.json"
          end

          def locomotive_auth_token
            return @auth_token unless @auth_token.nil?
            data = {
              query: {
                api_key: @locomotive_api_key
              }
            }
            @auth_token = JSON.parse(Locomotive::Wagon::Httparty::Webservice.post("http://#{@locomotive_url}/locomotive/api/tokens.json", data).body)["token"]
          end

          def render_all_without_cache(context)
            get_options_context context
            context.stack do
              begin
                context.scopes.last[@target.to_s] = Locomotive::Wagon::Httparty::Webservice.consume(render_url, @options.symbolize_keys)
                self.cached_response = context.scopes.last[@target.to_s]
              rescue Timeout::Error
                context.scopes.last[@target.to_s] = self.cached_response
              rescue ::Liquid::Error => e
                raise e
              rescue => e
                liquid_e = ::Liquid::Error.new(e.message, line)
                liquid_e.set_backtrace(e.backtrace)
                raise liquid_e
              end

              render_all(@nodelist, context)
            end
          end

          private

            def get_options_context(context)
              @options[:query].each do |key,value|
                @options[:query][key] = context[value] unless context[value].nil?
              end
            end

        end

        ::Liquid::Template.register_tag('consume_locomotive', ConsumeLocomotive)
      end
    end
  end
end
