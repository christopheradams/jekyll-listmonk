require "nokogiri"

module JekyllListmonk
  class HtmlProcessor
    def initialize(site_url: "", baseurl: "")
      @site_url = normalize_site_url(site_url)
      @baseurl = normalize_baseurl(baseurl)
    end

    # Converts relative img src attributes to absolute URLs
    def absolutize_img_srcs(html)
      return html.to_s if @site_url.empty?

      doc = Nokogiri::HTML.fragment(html.to_s)
      doc.css("img[src]").each do |img|
        src = img["src"].to_s
        absolute = absolutize_path(src)
        img["src"] = absolute if absolute
      end
      doc.to_html
    end

    # Converts relative href attributes to absolute URLs
    def absolutize_hrefs(html)
      return html.to_s if @site_url.empty?

      doc = Nokogiri::HTML.fragment(html.to_s)
      doc.css("a[href]").each do |link|
        href = link["href"].to_s
        absolute = absolutize_path(href, skip_special_protocols: true)
        link["href"] = absolute if absolute
      end
      doc.to_html
    end

    # Appends @TrackLink to eligible href URLs
    def rewrite_href_track_link(html)
      doc = Nokogiri::HTML.fragment(html.to_s)
      doc.css("a[href]").each do |link|
        href = link["href"].to_s.strip
        next if href.empty?
        next if href.include?(Constants::TRACK_LINK_SUFFIX)
        next if href.start_with?("#", *Constants::SPECIAL_HREF_PROTOCOLS)

        link["href"] = "#{href}#{Constants::TRACK_LINK_SUFFIX}"
      end
      doc.to_html
    end

    # Extracts all img src values from HTML
    def extract_img_srcs(html)
      doc = Nokogiri::HTML.fragment(html.to_s)
      doc.css("img[src]").map { |img| img["src"].to_s.strip }.reject(&:empty?).uniq
    end

    # Rewrites img src attributes based on a mapping
    def rewrite_img_srcs(html, mapping)
      return html.to_s if mapping.empty?

      doc = Nokogiri::HTML.fragment(html.to_s)
      doc.css("img[src]").each do |img|
        src = img["src"].to_s
        img["src"] = mapping[src] if mapping.key?(src)
      end
      doc.to_html
    end

    private

    def normalize_site_url(url)
      url.to_s.strip.sub(%r{/\z}, "")
    end

    def normalize_baseurl(baseurl)
      base = baseurl.to_s.strip
      base = "" if base == "/"
      base = "/#{base}" unless base.empty? || base.start_with?("/")
      base.sub(%r{/\z}, "")
    end

    def absolutize_path(raw_url, skip_special_protocols: false)
      return nil if raw_url.empty?

      # Preserve query/fragment while normalizing the path portion
      path, frag = raw_url.split("#", 2)
      path, query = path.split("?", 2)

      # Check for absolute or special protocols
      if path.start_with?("http://", "https://", "data:", "//")
        return nil
      end

      if skip_special_protocols && path.start_with?(*Constants::SPECIAL_HREF_PROTOCOLS)
        return nil
      end

      abs_path = path.start_with?("/") ? path : "#{@baseurl}/#{path}"
      abs_path = "/#{abs_path}" unless abs_path.start_with?("/")

      if !@baseurl.empty? && !abs_path.start_with?("#{@baseurl}/") && abs_path != @baseurl
        abs_path = @baseurl + abs_path
      end

      out = @site_url + abs_path
      out += "?#{query}" if query && !query.empty?
      out += "##{frag}" if frag && !frag.empty?
      out
    end
  end
end
