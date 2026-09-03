require 'net/http'
require 'uri'
require 'set'
require 'http_logger/configuration'
require 'http_logger/version'

# Usage:
#
#    require 'http_logger'
#
# == Setup logger
#
#    HttpLogger.configuration.logger = Logger.new('/tmp/all.log')
#    HttpLogger.configuration.log_headers = true
#
# == Do request
#
#     res = Net::HTTP.start(url.host, url.port) { |http|
#       http.request(req)
#     }
#     ...
#
# == View the log
#
#     cat /tmp/all.log
class HttpLogger
  AUTHORIZATION_HEADER = 'Authorization'

  def self.configuration
    @configuration ||= Configuration.new
  end

  def self.configure(&block)
    block.call(configuration)
  end


  def self.perform(*args, &block)
    instance.perform(*args, &block)
  end

  def self.instance
    @instance ||= HttpLogger.new
  end

  def perform(http, request, request_body)
    start_time = Time.now
    response = yield
  ensure
    if require_logging?(http, request)
      log_request_url(http, request, start_time)
      log_request_body(request, request_body)
      log_request_headers(request)
      if defined?(response) && response
        log_response_code(response)
        log_response_headers(response)
        log_response_body(response)
      end
    end
  end

  protected

  def binary_response?(response)
    content_type = response['Content-Type']
    return false if content_type.nil?

    !textual_content_type?(content_type)

  end

  def binary_request?(request)
    content_type = request['Content-Type']
    return false if content_type.nil?

    !textual_content_type?(content_type)
  end

  def log_request_url(http, request, start_time)
    ofset = Time.now - start_time
    log("HTTP #{request.method} (%0.2fms)" % (ofset * 1000), request_url(http, request))
  end

  def request_url(http, request)
    URI::DEFAULT_PARSER.unescape("http#{"s" if http.use_ssl?}://#{http.address}:#{http.port}#{request.path}")
  end

  def log_request_headers(request)
    if configuration.log_headers
      request.each_capitalized do |k,v|
        log_header(:request, k, v)
      end
    end
  end

  def log_header(type, name, value)
    value = "<filtered>" if filtered_header?(name)
    log("HTTP #{type} header", "#{name}: #{value}")
  end

  def filtered_header?(name)
    Array(configuration.filtered_headers).any? { |header| header.to_s.casecmp?(name.to_s) }
  end

  HTTP_METHODS_WITH_BODY = Set.new(%w(POST PUT GET PATCH))

  def log_request_body(request, request_body = nil)
    if configuration.log_request_body
      if HTTP_METHODS_WITH_BODY.include?(request.method)
        body = request.body || request_body
        if body && !body.empty?
          log("Request body", format_request_body_for_log(request, body))
        end
      end
    end
  end

  def log_response_code(response)
    log("Response status", "#{response.class} (#{response.code})")
  end

  def log_response_headers(response)
    if configuration.log_headers
      response.each_capitalized do |k,v|
        log_header(:response, k, v)
      end
    end
  end

  def log_response_body(response)
    if configuration.log_response_body
      body = response.body
      binary = binary_response?(response)
      if body.is_a?(Net::ReadAdapter)
        log("Response body", "<impossible to log>")
      else
        if body && !body.empty?
          log(
            "Response body",
            binary ? "<binary #{body.length} bytes>" : truncate_body(filter_body(body, response)),)
        end
      end
    end
  end

  def require_logging?(http, request)
    self.logger && !ignored?(http, request) && (http.started? || webmock?(http, request))
  end

  def ignored?(http, request)
    url = request_url(http, request)
    configuration.ignore.any? do |pattern|
      url =~ pattern
    end
  end

  def webmock?(http, request)
    return false unless defined?(::WebMock)
    uri = request_uri_as_string(http, request)
    method = request.method.downcase.to_sym
    signature = WebMock::RequestSignature.new(method, uri)
    ::WebMock.registered_request?(signature)
  end

  def request_uri_as_string(net_http, request)
    protocol = net_http.use_ssl? ? "https" : "http"

    path = request.path
    path = URI.parse(request.path).request_uri if request.path =~ /^http/

    if request["authorization"] =~ /^Basic /
      userinfo = WebMock::Utility.decode_userinfo_from_header(request["authorization"])
      userinfo = WebMock::Utility.encode_unsafe_chars_in_userinfo(userinfo) + "@"
    else
      userinfo = ""
    end

    "#{protocol}://#{userinfo}#{net_http.address}:#{net_http.port}#{path}"
  end

  def truncate_body(body)
    if collapse_body_limit && collapse_body_limit > 0 && body && body.size >= collapse_body_limit
      body_piece_size = collapse_body_limit / 2
      body[0..body_piece_size] +
        "\n\n<some data truncated>\n\n" +
        body[(body.size - body_piece_size)..body.size]
    else
      body
    end
  end

  def log(message, dump)
    self.logger.send(configuration.level, format_log_entry(message, dump))
  end

  def format_log_entry(message, dump = nil)
    if configuration.colorize
      message_color, dump_color = "4;32;1", "0;1"
      log_entry = "  \e[#{message_color}m#{message}\e[0m   "
      log_entry << "\e[#{dump_color}m%#{String === dump ? 's' : 'p'}\e[0m" % dump if dump
      log_entry
    else
      "%s  %s" % [message, dump]
    end
  end

  def logger
    configuration.logger
  end

  def collapse_body_limit
    configuration.collapse_body_limit
  end

  def textual_content_type?(content_type)
    normalized = content_type.to_s.downcase
    normalized.start_with?(
      'text/',
      'application/json',
      'application/xml',
      'application/javascript',
      'application/x-www-form-urlencoded',
      'application/xhtml+xml',
      'application/rss+xml',
      'application/atom+xml',
      'application/svg+xml',
      'application/yaml',
    )
  end

  def configuration
    self.class.configuration
  end

  def format_request_body_for_log(request, body)
    content_type = request['Content-Type']

    if multipart_content_type?(content_type)
      return truncate_body(sanitize_multipart_binary_parts(body, multipart_boundary(content_type)))
    end

    binary_request?(request) ? "<binary #{body.bytesize} bytes>" : truncate_body(filter_body(body, request))
  end

  # Hands a textual request or response body to the configured body_filter
  # before it is truncated and logged. Binary and multipart bodies skip it.
  def filter_body(body, request_or_response)
    filter = configuration.body_filter
    filter ? filter.call(body, request_or_response) : body
  end

  def multipart_content_type?(content_type)
    content_type.to_s.downcase.start_with?('multipart/')
  end

  def multipart_boundary(content_type)
    match = content_type.to_s.match(/boundary="?([^";]+)"?/i)
    match && match[1]
  end

  def sanitize_multipart_binary_parts(body, boundary)
    return body unless boundary

    binary_body = body.dup.force_encoding(Encoding::BINARY)
    delimiter = "--#{boundary}".b
    segments = binary_body.split(delimiter, -1)
    return body if segments.size < 2

    segments.each_with_index.map do |segment, index|
      if index == 0
        segment
      elsif segment.start_with?("--")
        "#{delimiter}#{segment}"
      else
        "#{delimiter}#{sanitize_multipart_segment(segment)}"
      end
    end.join
  end

  def sanitize_multipart_segment(segment)
    separator = if segment.include?("\r\n\r\n")
      "\r\n\r\n"
    elsif segment.include?("\n\n")
      "\n\n"
    end
    return segment unless separator

    headers, part_body = segment.split(separator, 2)
    return segment unless part_body

    content_type = headers.each_line.find { |line| line.downcase.start_with?('content-type:') }
    return segment unless content_type

    part_content_type = content_type.split(':', 2).last.to_s.strip
    return segment if textual_content_type?(part_content_type)

    trailing_newline = part_body.end_with?("\r\n") ? "\r\n" : (part_body.end_with?("\n") ? "\n" : "")
    payload = trailing_newline.empty? ? part_body : part_body[0...-trailing_newline.bytesize]
    "#{headers}#{separator}<binary #{payload.bytesize} bytes>#{trailing_newline}"
  end
end

block = lambda do |a|
  alias request_without_net_http_logger request
  def request(request, body = nil, &block)
    HttpLogger.perform(self, request, body) do
      request_without_net_http_logger(request, body, &block)
    end

  end
end

if defined?(::WebMock)
  klass = WebMock::HttpLibAdapters::NetHttpAdapter.instance_variable_get("@webMockNetHTTP")
  klass.class_eval(&block)
end


Net::HTTP.class_eval(&block)

if defined?(Rails)
  if defined?(ActiveSupport) && ActiveSupport.respond_to?(:on_load)
    # Rails3
    ActiveSupport.on_load(:after_initialize) do
      unless HttpLogger.configuration.logger
        HttpLogger.configuration.logger = Rails.logger
      end
    end
  end
end
