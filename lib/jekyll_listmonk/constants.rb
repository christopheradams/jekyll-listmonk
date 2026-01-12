module JekyllListmonk
  module Constants
    # Listmonk API paths
    API_LISTS = "/api/lists"
    API_CAMPAIGNS = "/api/campaigns"
    API_MEDIA = "/api/media"

    # Link tracking
    TRACK_LINK_SUFFIX = "@TrackLink"

    # Content types
    CONTENT_TYPE_HTML = "html"
    CONTENT_TYPE_MARKDOWN = "markdown"
    CONTENT_TYPE_JSON = "application/json"
    CONTENT_TYPE_MULTIPART = "multipart/form-data"
    CONTENT_TYPE_OCTET_STREAM = "application/octet-stream"

    # Campaign types
    CAMPAIGN_TYPE_REGULAR = "regular"

    # Supported output formats
    VALID_FORMATS = %w[html markdown].freeze

    # Protocols to skip when absolutizing URLs
    ABSOLUTE_PROTOCOLS = %w[http:// https:// data:// //].freeze
    SPECIAL_HREF_PROTOCOLS = %w[mailto: tel: sms: javascript: data:].freeze

    # Image file extensions
    IMAGE_EXTENSIONS_PNG = %w[.png].freeze
    IMAGE_EXTENSIONS_JPG = %w[.jpg .jpeg].freeze
  end
end
