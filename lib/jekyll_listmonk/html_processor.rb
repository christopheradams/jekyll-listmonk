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

    # Rewrites footnote HTML for email compatibility.
    #
    # Kramdown renders footnotes as internal page links which don't work in
    # emails.  This method:
    #   1. Replaces footnote reference links in the body with **<sup>N</sup>**
    #   2. Removes reverse-footnote backlinks (↩) from the footnotes section
    #   3. Strips the wrapper <div> and <hr>, leaving a clean <ol> list
    def rewrite_footnotes_for_email(html)
      doc = Nokogiri::HTML.fragment(html.to_s)

      # --- Footnote references in the body ---
      # Kramdown generates:
      #   <sup id="fnref:N" role="doc-noteref">
      #     <a href="#fn:N" class="footnote" rel="footnote">N</a>
      #   </sup>
      # Replace each <sup id="fnref:..."> with <sup><b>N</b></sup>.
      # The outer <sup> ensures reverse_markdown passes the whole node
      # through as raw HTML rather than converting <strong> to ** and
      # inserting a word-boundary space.
      doc.css("sup[id^='fnref']").each do |sup|
        num = sup.text.strip
        next if num.empty?

        strip_trailing_space(sup)
        sup.replace("<sup><b>#{escape_html(num)}</b></sup>")
      end

      # Catch any remaining standalone <a class="footnote"> links that were
      # not wrapped in a <sup> (varies by kramdown version / config).
      doc.css("a.footnote").each do |link|
        num = link.text.strip
        next if num.empty?

        strip_trailing_space(link)
        link.replace("<sup><b>#{escape_html(num)}</b></sup>")
      end

      # --- Footnotes section at the bottom ---
      # Kramdown generates:
      #   <div class="footnotes" role="doc-endnotes">
      #     <ol>
      #       <li id="fn:N" role="doc-endnote">
      #         <p>Content <a href="#fnref:N" class="reversefootnote">↩</a></p>
      #       </li>
      #     </ol>
      #   </div>
      footnotes_div = doc.at_css("div.footnotes")
      if footnotes_div
        # Remove ↩ backlinks
        footnotes_div.css("a.reversefootnote").each(&:remove)

        # Remove the <hr> separator kramdown may insert
        footnotes_div.css("hr").each(&:remove)

        # Strip page-internal IDs and ARIA roles from <li> elements
        footnotes_div.css("li").each do |li|
          li.remove_attribute("id")
          li.remove_attribute("role")
        end

        # Replace the wrapper <div> with just the <ol>
        ol = footnotes_div.at_css("ol")
        if ol
          footnotes_div.replace(ol)
        end
      end

      doc.to_html
    end

    private

    # Remove trailing whitespace from the text node immediately before +node+.
    # Kramdown often leaves a space between prose and the footnote <sup>,
    # e.g. "change. <sup>", which looks wrong after the link is removed.
    def strip_trailing_space(node)
      prev = node.previous
      if prev && prev.text?
        prev.content = prev.content.sub(/\s+\z/, "")
      end
    end

    def escape_html(text)
      text.to_s
        .gsub("&", "&amp;")
        .gsub("<", "&lt;")
        .gsub(">", "&gt;")
        .gsub('"', "&quot;")
    end

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
      return nil if raw_url.nil? || raw_url.empty?

      # Fragment-only URLs (e.g. "#fn:1") are page-internal anchors and
      # must not be turned into absolute URLs.
      return nil if raw_url.start_with?("#")

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
