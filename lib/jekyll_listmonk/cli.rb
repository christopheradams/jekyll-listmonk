require "optparse"
require "tmpdir"

module JekyllListmonk
  class CLI
    def self.run(argv)
      new(argv).run
    rescue Interrupt
      warn "Interrupted."
      130
    rescue StandardError => e
      warn "Error: #{e.message}"
      1
    end

    def initialize(argv)
      @argv = argv.dup
      @picture_tag_preset = nil
      @track_link = false
    end

    def run
      global = OptionParser.new do |o|
        o.banner = "Usage: jekyll-listmonk <command> [args]\n\nCommands: preview, campaign, upload"
        o.on("--picture-tag-preset PRESET", "Force Jekyll Picture Tag preset for rewritten `{% picture %}` tags") do |v|
          v = v.to_s.strip
          @picture_tag_preset = v.empty? ? nil : v
        end
        o.on("--track_links", "Append @TrackLink to every eligible href URL") do
          @track_link = true
        end
        o.on("-h", "--help", "Show help") { puts o; return 0 }
      end
      global.parse!(@argv)

      cmd = @argv.shift
      raise "Missing command (preview|campaign|upload)" if cmd.nil? || cmd.empty?

      case cmd
      when "preview"
        post = @argv.shift
        raise "Missing post identifier" if post.nil? || post.empty?

        renderer = JekyllPostRenderer.new(source_dir: Dir.pwd, picture_tag_preset: @picture_tag_preset)
        rendered = renderer.render_post_fragment!(post)
        html = rendered[:html].to_s
        html = rewrite_href_track_link(html) if @track_link

        puts html
        0
      when "campaign"
        upload_media = false
        format = "html"
        campaign_opts = OptionParser.new do |o|
          o.on("--upload-media", "Upload referenced images to Listmonk media and rewrite HTML to use returned URLs") do
            upload_media = true
          end
          o.on("--format FORMAT", "Campaign format: html (default) or markdown") do |v|
            format = v.to_s.strip.downcase
          end
        end
        campaign_opts.parse!(@argv)
        raise "Invalid --format #{format.inspect} (expected html|markdown)" unless %w[html markdown].include?(format)

        post = @argv.shift
        raise "Missing post identifier" if post.nil? || post.empty?

        renderer = JekyllPostRenderer.new(source_dir: Dir.pwd, picture_tag_preset: @picture_tag_preset)
        rendered = nil
        html = nil
        dry_run = ENV["DRY_RUN"].to_s == "1"

        if upload_media
          Dir.mktmpdir("jekyll-listmonk-site-") do |dest|
            rendered = renderer.render_post_fragment!(post, destination_dir: dest)
            html = rendered[:html].to_s
            unless dry_run
              client = ListmonkClient.from_env
              html = rewrite_html_with_uploaded_media!(html, dest, client: client,
                                                             baseurl: rendered[:baseurl].to_s,
                                                             site_url: rendered[:site_url].to_s)
            end
          end
        else
          rendered = renderer.render_post_fragment!(post)
          html = rendered[:html].to_s
        end
        html = rewrite_href_track_link(html) if @track_link

        content_type = "html"
        body = html
        if format == "markdown"
          content_type = "markdown"
          body = html_to_markdown(body)
        end

        if dry_run
          puts body
          warn "DRY_RUN=1 set, not calling Listmonk."
          return 0
        end

        client = ListmonkClient.from_env

        name = ENV["LISTMONK_CAMPAIGN_NAME"].to_s
        name = rendered[:title].to_s if name.empty?

        subject = ENV["LISTMONK_SUBJECT"].to_s
        subject = rendered[:title].to_s if subject.empty?

        list_ids = ENV.fetch("LISTMONK_LIST_IDS").split(",").map(&:strip).reject(&:empty?).map(&:to_i)
        raise "LISTMONK_LIST_IDS must contain at least one list id" if list_ids.empty?

        type = ENV.fetch("LISTMONK_CAMPAIGN_TYPE", "regular")

        template_id = ENV["LISTMONK_TEMPLATE_ID"]&.to_s&.strip
        template_id = template_id.to_i if template_id && !template_id.empty?

        from_email = ENV["LISTMONK_FROM_EMAIL"]
        from_name = ENV["LISTMONK_FROM_NAME"]
        tags = ENV["LISTMONK_TAGS"]&.split(",")&.map(&:strip)&.reject(&:empty?)

        res = client.create_campaign!(
          name: name,
          subject: subject,
          lists: list_ids,
          body: body,
          content_type: content_type,
          type: type,
          template_id: template_id,
          from_email: from_email,
          from_name: from_name,
          tags: tags
        )

        id = res.dig("data", "id") || res["id"]
        warn "Created Listmonk campaign id=#{id || "(unknown)"}"
        0
      when "upload"
        path = @argv.shift
        raise "Missing file path" if path.nil? || path.empty?

        client = ListmonkClient.from_env
        res = client.upload_media!(path)

        data = res["data"]
        id = data.is_a?(Hash) ? data["id"] : nil

        direct_url = data.is_a?(Hash) ? data["url"].to_s : ""
        url = direct_url

        if id && !url.empty?
          puts "Uploaded media id=#{id} url=#{url}"
        else
          # Fall back to raw response so there's always visible output.
          puts res.inspect
        end
        0
      else
        raise "Unknown command: #{cmd.inspect} (expected preview|campaign|upload)"
      end
    end

    private

    def rewrite_html_with_uploaded_media!(html, destination_dir, client:, baseurl:, site_url:)
      srcs = extract_img_srcs(html)
      warn "No <img src=...> found to upload." if srcs.empty?
      return html if srcs.empty?

      baseurl_norm = baseurl.to_s.strip
      baseurl_norm = "" if baseurl_norm == "/"
      baseurl_norm = "/#{baseurl_norm}" unless baseurl_norm.empty? || baseurl_norm.start_with?("/")
      baseurl_norm = baseurl_norm.sub(%r{/\z}, "")

      site_url_norm = site_url.to_s.strip.sub(%r{/\z}, "")

      mapping = {}
      srcs.each do |src|
        next if src.start_with?("data:")

        # Support both site-relative paths ("/assets/foo.jpg") and absolute URLs
        # that point at this site (eg. "https://example.com/assets/foo.jpg").
        path =
          if src.start_with?("http://", "https://")
            if !site_url_norm.empty? && (src.start_with?(site_url_norm + "/") || src == site_url_norm)
              src.sub(site_url_norm, "")
            else
              next
            end
          elsif src.start_with?("//")
            # Protocol-relative URL. Only handle if we can match the configured site URL.
            if !site_url_norm.empty? && site_url_norm.sub(%r{\Ahttps?:}, "") != "" &&
                 (src.start_with?(site_url_norm.sub(%r{\Ahttps?:}, "") + "/") || src == site_url_norm.sub(%r{\Ahttps?:}, ""))
              src.sub(site_url_norm.sub(%r{\Ahttps?:}, ""), "")
            else
              next
            end
          else
            src.dup
          end

        path = path.split("#", 2).first
        path = path.split("?", 2).first

        if !baseurl_norm.empty? && path.start_with?(baseurl_norm + "/")
          path = path.sub(baseurl_norm, "")
        elsif path == baseurl_norm
          next
        end

        fs_rel = path.to_s.sub(%r{\A/}, "")
        next if fs_rel.empty?
        fs_path = File.join(destination_dir.to_s, fs_rel)

        # Prefer a .jpg/.jpeg variant if the HTML references a .png but Jekyll produced both.
        preferred_path = fs_path
        if File.extname(preferred_path).downcase == ".png"
          jpg = preferred_path.sub(/\.png\z/i, ".jpg")
          jpeg = preferred_path.sub(/\.png\z/i, ".jpeg")
          preferred_path = jpg if File.file?(jpg)
          preferred_path = jpeg if preferred_path == fs_path && File.file?(jpeg)
        end

        raise "Could not find local file for img src=#{src.inspect} (looked for #{preferred_path})" unless File.file?(preferred_path)

        next if mapping.key?(src)
        res = client.upload_media!(preferred_path)
        url = res.dig("data", "url").to_s
        id = res.dig("data", "id")
        raise "Listmonk media upload did not return data.url for #{preferred_path}" if url.empty?

        warn "Uploaded media id=#{id || "(unknown)"} src=#{src} url=#{url}"
        mapping[src] = url
      end

      rewrite_img_srcs(html, mapping)
    end

    def extract_img_srcs(html)
      # Minimal extraction for rendered Jekyll HTML.
      # Matches:
      # - <img ... src="...">
      # - <img ... src='...'>
      # - <img ... src=/path/to/file>
      html.to_s
          .scan(/<img\b[^>]*\bsrc=(?:"([^"]+)"|'([^']+)'|([^\s>]+))/i)
          .map { |a, b, c| a || b || c }
          .map(&:to_s)
          .map(&:strip)
          .reject(&:empty?)
          .uniq
    end

    def rewrite_img_srcs(html, mapping)
      out = html.to_s
      mapping.each do |old_src, new_src|
        # Replace quoted or unquoted src attribute values that exactly match old_src.
        out = out.gsub(/(<img\b[^>]*\bsrc=)(?:"#{Regexp.escape(old_src)}"|'#{Regexp.escape(old_src)}'|#{Regexp.escape(old_src)})(?=[\s>])/i) do
          %(#{$1}"#{new_src}")
        end
      end
      out
    end

    def rewrite_href_track_link(html)
      out = html.to_s
      # Matches:
      # - href="..."/'...'
      # - href=... (unquoted)
      out.gsub(/(\bhref=)(?:"([^"]+)"|'([^']+)'|([^\s>]+))/i) do
        prefix = Regexp.last_match(1)
        href = Regexp.last_match(2) || Regexp.last_match(3) || Regexp.last_match(4) || ""
        href = href.to_s.strip

        if href.empty? ||
             href.include?("@TrackLink") ||
             href.start_with?("#", "mailto:", "tel:", "sms:", "javascript:", "data:")
          %(#{prefix}"#{href}")
        else
          %(#{prefix}"#{href}@TrackLink")
        end
      end
    end

    def html_to_markdown(html)
      begin
        require "reverse_markdown"
      rescue LoadError => e
        raise "reverse_markdown is required for --format markdown (#{e.message}). Add it to your bundle or install it."
      end

      ReverseMarkdown.convert(html.to_s)
    end
  end
end

