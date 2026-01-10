require "json"
require "net/http"
require "uri"
require "securerandom"

module JekyllListmonk
  class ListmonkClient
    class Error < StandardError; end

    def self.from_env
      base_url = ENV.fetch("LISTMONK_URL")
      username = ENV.fetch("LISTMONK_USER")
      token = ENV.fetch("LISTMONK_TOKEN")
      use_token_header = ENV.fetch("LISTMONK_AUTH_MODE", "").downcase == "header"

      new(base_url: base_url, username: username, token: token, use_token_header: use_token_header)
    end

    # Auth modes supported by listmonk:
    # - Basic auth: username=api_user, token=api_token (sent as user:token)
    # - Authorization header: "token api_user:api_token"
    #
    # This client supports both. By default, it uses Basic auth.
    def initialize(base_url:, username:, token:, use_token_header: false, timeout: 30)
      @base_uri = URI(base_url)
      @username = username
      @token = token
      @use_token_header = use_token_header
      @timeout = timeout
    end

    def create_campaign!(
      name:,
      subject:,
      lists:,
      body: nil,
      content_type: "html",
      html_body: nil,
      type: "regular",
      template_id: nil,
      from_email: nil,
      from_name: nil,
      tags: nil
    )
      body = html_body if body.nil?
      raise Error, "Missing campaign body" if body.nil?

      payload = {
        name: name,
        subject: subject,
        lists: lists,
        type: type,
        content_type: content_type,
        body: body
      }

      payload[:template_id] = template_id if template_id
      payload[:from_email] = from_email if from_email && !from_email.empty?
      payload[:from_name] = from_name if from_name && !from_name.empty?
      payload[:tags] = tags if tags && !tags.empty?

      post_json!("/api/campaigns", payload)
    end

    # Upload a media file. Returns parsed JSON response.
    # https://listmonk.app/docs/apis/media/
    def upload_media!(file_path)
      path = file_path.to_s
      raise Error, "File not found: #{path}" unless File.file?(path)

      filename = File.basename(path)
      file_bytes = File.binread(path)

      boundary = "--------------------------#{SecureRandom.hex(12)}"
      body = +""
      body << "--#{boundary}\r\n"
      body << %(Content-Disposition: form-data; name="file"; filename="#{filename}"\r\n)
      body << "Content-Type: application/octet-stream\r\n\r\n"
      body << file_bytes
      body << "\r\n--#{boundary}--\r\n"

      post_multipart!("/api/media", body, boundary: boundary)
    end

    # Convert a relative `/uploads/...` path to a full URL using LISTMONK_URL.
    def absolute_url(path_or_url)
      s = path_or_url.to_s.strip
      return "" if s.empty?
      return s if s.start_with?("http://", "https://")

      base = @base_uri.dup
      base.path = ""
      base.query = nil
      base.fragment = nil
      base.to_s.sub(%r{/\z}, "") + (s.start_with?("/") ? s : "/#{s}")
    end

    private

    def join_uri_path(base_path, extra_path)
      base = base_path.to_s
      extra = extra_path.to_s

      base = "" if base == "/"
      base = base.sub(%r{/\z}, "")
      extra = extra.sub(%r{\A/}, "")

      joined = [base, extra].reject(&:empty?).join("/")
      joined.start_with?("/") ? joined : "/#{joined}"
    end

    def http_for(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = @timeout
      http.read_timeout = @timeout
      http
    end

    def post_json!(path, payload)
      uri = @base_uri.dup
      uri.path = join_uri_path(uri.path, path)

      req = Net::HTTP::Post.new(uri)
      req["Accept"] = "application/json"
      req["Content-Type"] = "application/json"
      req.body = JSON.dump(payload)

      apply_auth!(req)

      request_json!(uri, req)
    end

    def post_multipart!(path, body, boundary:)
      uri = @base_uri.dup
      uri.path = join_uri_path(uri.path, path)

      req = Net::HTTP::Post.new(uri)
      req["Accept"] = "application/json"
      req["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
      req.body = body

      apply_auth!(req)
      request_json!(uri, req)
    end

    def request_json!(uri, req)
      res = http_for(uri).request(req)
      body = res.body.to_s

      raise Error, "Listmonk API error (HTTP #{res.code}): #{body}" unless res.is_a?(Net::HTTPSuccess)

      JSON.parse(body)
    rescue JSON::ParserError
      raise Error, "Listmonk API returned non-JSON response (HTTP #{res&.code}): #{body}"
    end

    def apply_auth!(req)
      if @use_token_header
        req["Authorization"] = "token #{@username}:#{@token}"
      else
        req.basic_auth(@username, @token)
      end
    end
  end
end

