# Net::HTTP logger

Simple gem that logs your HTTP api requests just like database queries


## Screenshot

* [Hoptoad](https://github.com/railsware/http_logger/raw/master/screenshots/hoptoad.png)
* [Simple get](https://github.com/railsware/http_logger/raw/master/screenshots/rails_console.png)
* [Solr](https://github.com/railsware/http_logger/raw/master/screenshots/solr.png)

## Installation

``` sh
gem install http_logger
```

## Usage

``` ruby
require 'http_logger'

HttpLogger.configure do |c|
  # defaults to Rails.logger if Rails is defined
  c.logger = Logger.new(LOGFILE)

  # Default: true
  c.colorize = true

  # Ignore patterns (e.g., URLs to ignore)
  c.ignore = [/newrelic\.com/]

  # Default: false
  c.log_headers = false

  # Default: true
  c.log_request_body = false

  # Default: true
  c.log_response_body = false

  # Desired log level as a symbol. Default: :debug
  c.level = :info

  # Change default truncate limit. Default: 5000
  c.collapse_body_limit = 5000

  # Header names whose values are logged as <filtered>, case-insensitive.
  # Default: ["Authorization"]. Setting it replaces the default rather than
  # adding to it; an empty list logs every header in full.
  c.filtered_headers = %w[Authorization X-Api-Key]
  # Called with each textual request or response body before it is truncated
  # and logged, together with the Net::HTTP request or response it belongs
  # to. Return the string to log. Binary and multipart bodies skip it.
  # Use `is_a?(Net::HTTPResponse)` to tell the two apart. The body arrives
  # ASCII-8BIT, so keep patterns ASCII-only or force_encoding a copy first.
  # A filter that raises logs a placeholder instead of breaking the request.
  # Default: nil
  c.body_filter = lambda do |body, request_or_response|
    body.gsub(/"(access|refresh)_token":\s*"[^"]*"/, '"\\1_token":"<filtered>"')
  end
end
```

## Alternative

Net::HTTP has a builtin logger that can be set via \#set\_debug\_output.
This method is only available at the instance level and it is not always accessible if used inside of a library. Also output of builtin debugger is not formed well for API debug purposes.

## Integration

If you are using Net::HTTP#request hackers like FakeWeb make sure you require http\_logger after all others because http\_logger always calls "super", rather than others.
