require 'spec_helper'
require "uri"
require "base64"

describe HttpLogger do

  before do
    # flush log
    f = File.open(LOGFILE, "w")
    f.close

    stub_request(:any, url).to_return(
      body: response_body,
      headers: {"X-Http-logger" => true, **response_headers},
    )
  end

  let(:response_body) { "Success" }
  let(:response_headers) { {} }
  let(:request_headers) { {} }

  let(:url) { "http://google.com/" }
  let(:uri) { URI.parse(url) }
  let(:request) do
    Net::HTTP.get_response(uri, **request_headers)
  end

  let(:long_body) do
    "12,Dodo case,dodo@case.com,tech@dodcase.com,single elimination\n" * 50 +
      "12,Bonobos,bono@bos.com,tech@bonobos.com,double elimination\n" * 50
  end

  subject do
    _context if defined?(_context)
    request
    File.read(LOGFILE)
  end

  it { should_not be_empty }

  context "when url has escaped chars" do

    let(:url) { "http://google.com?query=a%20b"}

    it { subject.should include("query=a b")}

  end

  context "when headers logging is on" do

    before(:each) do
      HttpLogger.configuration.log_headers = true
    end

    it { should include("HTTP response header") }
    it { should include("HTTP request header") }


    context "authorization header" do

      let(:request_headers) do
        {'Authorization' => "Basic #{Base64.encode64('hello:world')}".strip}
      end
      it { should include("Authorization: <filtered>") }
    end
  end

  describe "post request" do
    let(:body) {{:a => 'hello', :b => 1}}
    let(:request) do
      Net::HTTP.post_form(uri, body)
    end

    it {should include("Request body")}
    it {should include("a=hello&b=1")}
    context "with too long body" do
      let(:response_body) { long_body }
      let(:url) do
        "http://github.com/"
      end
      it { should include("12,Dodo case,dodo@case.com,tech@dodcase.com,single elimination\n")}
      it { should include("<some data truncated>") }
      it { should include("12,Bonobos,bono@bos.com,tech@bonobos.com,double elimination\n")}
    end

  end

  describe "put request" do
    let(:request) do
      http = Net::HTTP.new(uri.host, uri.port)
      request = Net::HTTP::Put.new(uri.path)
      request.set_form_data(:a => 'hello', :b => 1)
      http.request(request)
    end

    it {should include("Request body")}
    it {should include("a=hello&b=1")}
  end

  describe "generic request" do
    let(:request) do
      http = Net::HTTP.new(uri.host, uri.port)
      request = Net::HTTPGenericRequest.new('PUT', true, true, uri.path)
      request.body = "a=hello&b=1"
      http.request(request)
    end

    it {should include("Request body")}
    it {should include("a=hello&b=1")}
  end

  context "when request body logging is off" do

    before(:each) do
      HttpLogger.configuration.log_request_body = false
    end

    let(:request) do
      Net::HTTP.post_form(uri, {})
    end

    it { should_not include("Request body") }

  end

  context "with long response body" do

    let(:response_body) { long_body }
    let(:url) do
      stub_request(:get, "http://github.com/").to_return(body: long_body)
      "http://github.com"
    end

    it { should include("12,Dodo case,dodo@case.com,tech@dodcase.com,single elimination\n")}
    it { should include("<some data truncated>") }
    it { should include("12,Bonobos,bono@bos.com,tech@bonobos.com,double elimination\n")}

  end

  context "when response body logging is off" do

    before(:each) do
      HttpLogger.configuration.log_response_body = false
    end

    let(:response_body) { long_body }
    let(:url) do
      "http://github.com"
    end

    it { should_not include("Response body") }
  end

  context "ignore option is set" do

    let(:url) do
      "http://rpm.newrelic.com/hello/world"
    end

    before(:each) do
      HttpLogger.configuration.ignore = [/rpm\.newrelic\.com/]
    end

    it { should be_empty}
  end

  context "when level is set" do

    let(:url) do
      stub_request(:get, "http://rpm.newrelic.com/hello/world").to_return(body: "")
      "http://rpm.newrelic.com/hello/world"
    end

    before(:each) do
      HttpLogger.configuration.level = :info
    end

    it { should_not be_empty }
  end

  context "when binary response" do
    let(:response_headers) do
      {
        'Content-Type' => 'image/webp'
      }
    end
    let(:url) do
      "http://example.com/image.webp"
    end

    let(:response_body) do
      File.read("#{File.dirname(__FILE__)}/image.webp")
    end

    it { should include("<binary 41887 bytes>") }
  end

  context "when binary request" do
    let(:url) { "http://example.com/upload" }
    let(:request) do
      http = Net::HTTP.new(uri.host, uri.port)
      request = Net::HTTP::Post.new(uri.path)
      request['Content-Type'] = 'image/jpeg'
      request.body = "\xFF\xD8\xFF\xDBbinarypayload".b
      http.request(request)
    end

    it { should include("Request body") }
    it { should include("<binary 17 bytes>") }
    it { should_not include("binarypayload") }
  end

  context "when multipart request has binary and text parts" do
    let(:url) { "http://example.com/upload" }
    let(:boundary) { "turing-export-80cd207c6b0b5f0c" }
    let(:request) do
      http = Net::HTTP.new(uri.host, uri.port)
      request = Net::HTTP::Post.new(uri.path)
      request['Content-Type'] = "multipart/related; boundary=#{boundary}"
      request.body = <<~BODY.chomp
        --#{boundary}
        Content-Type: application/json; charset=UTF-8

        {"name":"IMG_20190921_152700.jpg","parents":["1LxERY9t0fCAJXJBvBSIGAVhP4IpD0Iyv"]}
        --#{boundary}
        Content-Type: image/jpeg

        \xFF\xD8\xFF\xDBJPEGDATA
        --#{boundary}--
      BODY
      http.request(request)
    end

    it { should include(%({"name":"IMG_20190921_152700.jpg","parents":["1LxERY9t0fCAJXJBvBSIGAVhP4IpD0Iyv"]})) }
    it { should include("Content-Type: image/jpeg") }
    it { should include("<binary 12 bytes>") }
    it { should_not include("JPEGDATA") }
  end

  after(:each) do
    HttpLogger.configuration.reset
  end

  describe "filtered_headers" do
    before(:each) do
      HttpLogger.configuration.log_headers = true
    end

    let(:request_headers) do
      {'Authorization' => "Bearer secret", 'X-Api-Key' => "key123"}
    end

    it "filters Authorization by default and leaves other headers alone" do
      subject.should include("Authorization: <filtered>")
      subject.should include("X-Api-Key: key123")
    end

    context "with a custom list" do
      before(:each) do
        HttpLogger.configuration.filtered_headers = %w[x-api-key]
      end

      it "matches case-insensitively and no longer filters Authorization" do
        subject.should include("X-Api-Key: <filtered>")
        subject.should include("Authorization: Bearer secret")
      end
    end

    context "with an empty list" do
      before(:each) do
        HttpLogger.configuration.filtered_headers = []
      end

      it "logs every header in full" do
        subject.should include("Authorization: Bearer secret")
        subject.should include("X-Api-Key: key123")
      end
    end

    context "with response headers" do
      let(:response_headers) { {'Set-Cookie' => "session=abc"} }

      before(:each) do
        HttpLogger.configuration.filtered_headers = %w[Authorization Set-Cookie]
      end

      it { should include("Set-Cookie: <filtered>") }
    end
  end
end
