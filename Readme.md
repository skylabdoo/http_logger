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
  # and logged. Return the string to log. Binary and multipart bodies skip
  # it. Takes the body alone, or the body plus the Net::HTTP request or
  # response it belongs to. Default: nil
  c.body_filter = lambda do |body|
    body.gsub(/"(access|refresh)_token":\s*"[^"]*"/, '"\\1_token":"<filtered>"')
  end
end
```

### Writing a body filter

**Return the new string.** The most common mistake is reaching for `gsub!`,
which returns `nil` when it matches nothing. A `nil` return logs an empty
body, so the moment a payload has no token in it the body disappears from
your log:

```ruby
# BAD -- logs nothing at all for any body without a token
c.body_filter = lambda { |body| body.gsub!("secret", "<filtered>") }

# GOOD -- gsub always returns a string
c.body_filter = lambda { |body| body.gsub("secret", "<filtered>") }
```

The filter is handed a copy, so mutating its argument cannot corrupt the
body your application reads -- but the return value is still what gets
logged.

**Take one argument or two.** The second argument is the `Net::HTTP`
request or response the body came from, for filters that need to branch:

```ruby
c.body_filter = lambda do |body, request_or_response|
  if request_or_response.is_a?(Net::HTTPResponse)
    body.gsub(/"token":"[^"]*"/, '"token":"<filtered>"')
  else
    body
  end
end
```

**Mind the encoding.** Response bodies arrive `ASCII-8BIT` -- `Net::HTTP`
does not apply the `Content-Type` charset unless you set
`response.body_encoding`. Request bodies keep whatever encoding your
application gave them, usually `UTF-8`. A non-ASCII pattern against a
binary body raises `Encoding::CompatibilityError`, so either keep patterns
ASCII-only or `force_encoding` a copy first.

**Failures are contained.** A filter that raises logs
`<body_filter raised SomeErrorClass>` instead of the body, and never
interrupts the HTTP call it is observing. The exception message is
deliberately omitted, because it can quote the body the filter was
supposed to mask.

## Alternative

Net::HTTP has a builtin logger that can be set via \#set\_debug\_output.
This method is only available at the instance level and it is not always accessible if used inside of a library. Also output of builtin debugger is not formed well for API debug purposes.

## Integration

If you are using Net::HTTP#request hackers like FakeWeb make sure you require http\_logger after all others because http\_logger always calls "super", rather than others.
