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
      @dry_run = false
    end

    def run
      # Try to load dotenv for development convenience
      begin
        require "dotenv"
        Dotenv.load
      rescue LoadError
        # dotenv not available, ignore
      end

      # Capture global options first
      global_options = {}
      global = OptionParser.new do |o|
        o.banner = "Usage: jekyll-listmonk <command> [args]\n\nCommands: campaign, upload, lists"
        o.on("--dry-run", "Render/print output but do not call Listmonk APIs") do
          global_options[:dry_run] = true
        end
        o.on("--url URL", "Listmonk URL") do |v|
          global_options[:url] = v
        end
        o.on("--user USER", "Listmonk Username") do |v|
          global_options[:user] = v
        end
        o.on("--token TOKEN", "Listmonk Token") do |v|
          global_options[:token] = v
        end
        o.on("-h", "--help", "Show help") { puts o; return 0 }
      end
      
      # Important: stop parsing at the subcommand so command-specific flags
      # (eg. `campaign --dry-run`) don't get treated as global options.
      global.order!(@argv)

      cmd = @argv.shift
      raise "Missing command (campaign|upload)" if cmd.nil? || cmd.empty?

      # Store global options for later use in config resolution
      @global_options = global_options
      @dry_run = global_options[:dry_run]

      case cmd
      when "lists"
        client = client_from_config
        res = client.get_lists
        lists = res.dig("data", "results") || []
        if lists.empty?
          puts "No lists found."
        else
          puts "Available Lists:"
          lists.each do |l|
            puts "  [#{l['id']}] #{l['name']} (#{l['type']})"
          end
        end
        0
      when "campaign"
        # dry_run can be set globally or per-command. Inherit global if set.
        dry_run = @dry_run
        test_email = nil
        
        # Command-specific config overrides
        cmd_config = {}

        campaign_opts = OptionParser.new do |o|
          o.on("--upload-media", "Upload referenced images to Listmonk media and rewrite HTML to use returned URLs") do
            cmd_config[:upload_media] = true
          end
          o.on("--format FORMAT", "Campaign format: html (default) or markdown") do |v|
             cmd_config[:format] = v.to_s.strip.downcase
          end
          o.on("--picture-tag-preset PRESET", "Force Jekyll Picture Tag preset for rewritten `{% picture %}` tags") do |v|
            v = v.to_s.strip
            cmd_config[:picture_tag_preset] = v.empty? ? nil : v
          end
          o.on("--track-links", "Append @TrackLink to every eligible href URL") do
             cmd_config[:track_links] = true
          end
          o.on("--frontmatter-image", "Inject the post frontmatter `image` at the top of the body") do
             cmd_config[:include_frontmatter_image] = true
          end
          o.on("--test-email EMAIL", "Send a test email to this address for the created campaign") do |v|
            test_email = v.to_s.strip
          end
          o.on("--lists LIST_IDS", "Comma-separated list IDs") do |v|
            cmd_config[:list_ids] = v.to_s.split(",").map(&:strip).reject(&:empty?).map(&:to_i)
          end
          o.on("--subject SUBJECT", "Campaign subject") do |v|
            cmd_config[:subject] = v
          end
          o.on("--name NAME", "Campaign name") do |v|
             cmd_config[:campaign_name] = v
          end
          o.on("--from-email EMAIL", "From email") do |v|
            cmd_config[:from_email] = v
          end
          o.on("--from-name NAME", "From name") do |v|
            cmd_config[:from_name] = v
          end
          o.on("--tags TAGS", "Comma-separated tags") do |v|
            cmd_config[:tags] = v.to_s.split(",").map(&:strip).reject(&:empty?)
          end
          o.on("--template-id ID", "Template ID") do |v|
             cmd_config[:template_id] = v.to_i
          end
          # Allow `campaign --dry-run` for convenience.
          o.on("--dry-run", "Alias for global --dry-run") { dry_run = true }
        end
        campaign_opts.parse!(@argv)
        if cmd_config[:format] && !%w[html markdown].include?(cmd_config[:format])
          raise "Invalid --format #{cmd_config[:format].inspect} (expected html|markdown)"
        end

        # Merge command-specific config into global options for resolution
        @cmd_config = cmd_config
        cfg = resolve_config

        post = @argv.shift
        raise "Missing post identifier" if post.nil? || post.empty?
        
        # Load params from config
        upload_media = cfg[:upload_media]
        format = cfg[:format] || "html"
        picture_tag_preset = cfg[:picture_tag_preset]
        track_links = cfg[:track_links]
        include_frontmatter_image = cfg[:include_frontmatter_image]

        renderer = JekyllPostRenderer.new(source_dir: Dir.pwd, picture_tag_preset: picture_tag_preset)
        rendered = nil
        html = nil

        if upload_media
          Dir.mktmpdir("jekyll-listmonk-site-") do |dest|
            rendered = renderer.render_post_fragment!(post,
                                                      destination_dir: dest,
                                                      inject_frontmatter_picture_tag: true,
                                                      inject_frontmatter_image: include_frontmatter_image)
            html = rendered[:html].to_s
            html = absolutize_img_srcs(html, site_url: rendered[:site_url].to_s, baseurl: rendered[:baseurl].to_s)
            if dry_run
              html = rewrite_html_with_guessed_media_urls!(html, dest,
                                                          listmonk_url: resolve_config[:url],
                                                          baseurl: rendered[:baseurl].to_s,
                                                          site_url: rendered[:site_url].to_s)
            else
              client = client_from_config
              html = rewrite_html_with_uploaded_media!(html, dest, client: client,
                                                             baseurl: rendered[:baseurl].to_s,
                                                             site_url: rendered[:site_url].to_s)
            end
          end
        else
          # If we are not uploading media, don't inject a `{% picture %}` tag for the
          # frontmatter image. Fall back to a plain Markdown image instead so the email
          # doesn't depend on picture-tag-generated derivatives existing in the site build.
          rendered = renderer.render_post_fragment!(post,
                                                    inject_frontmatter_picture_tag: false,
                                                    inject_frontmatter_image: include_frontmatter_image)
          html = rendered[:html].to_s
          html = absolutize_img_srcs(html, site_url: rendered[:site_url].to_s, baseurl: rendered[:baseurl].to_s)
        end
        html = rewrite_href_track_link(html) if track_links

        content_type = "html"
        body = html
        if format == "markdown"
          content_type = "markdown"
          body = html_to_markdown(body)
        end

        if dry_run
          puts body
          warn "--dry-run set, not calling Listmonk."
          return 0
        end

        client = client_from_config
        # cfg already resolved earlier

        name = cfg[:campaign_name].to_s
        name = rendered[:title].to_s if name.empty?

        subject = cfg[:subject].to_s
        subject = rendered[:title].to_s if subject.empty?

        list_ids = cfg[:list_ids].map(&:to_i)
        if list_ids.empty?
          input = prompt_for("List IDs (comma separated)")
          list_ids = input.to_s.split(",").map(&:strip).reject(&:empty?).map(&:to_i)
        end
        raise "LISTMONK_LIST_IDS must contain at least one list id" if list_ids.empty?

        type = cfg[:campaign_type]

        template_id = cfg[:template_id]&.to_s&.strip
        template_id = template_id.to_i if template_id && !template_id.empty?

        from_email = cfg[:from_email]
        from_name = cfg[:from_name]
        tags = cfg[:tags]

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
        
        if test_email && id
          warn "Sending test email to #{test_email}..."
          client.test_campaign!(id, test_email)
          warn "Test email sent."
        end

        0
      when "upload"
        path = @argv.shift
        raise "Missing file path" if path.nil? || path.empty?

        if @dry_run
          puts "DRY RUN: would upload #{path.inspect}"
          return 0
        end

        client = client_from_config
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
        raise "Unknown command: #{cmd.inspect} (expected campaign|upload)"
      end
    end

    private

    def resolve_config
      return @config if @config

      # Try to load Jekyll config
      begin
        require "jekyll"
        # Mute Jekyll's output
        Jekyll.logger.log_level = :error
        site_config = Jekyll.configuration({}) rescue {}
        lm_config = site_config["listmonk"] || {}
      rescue LoadError
        lm_config = {}
      end

      @global_options ||= {}
      @cmd_config ||= {}

      # Helper to merge: flag > env > config
      fetch = ->(flag_key, env_key, config_key) {
        val = @global_options[flag_key] || @cmd_config[flag_key]
        return val unless val.nil?

        ENV[env_key] || lm_config[config_key]
      }

      list_ids = fetch.call(:list_ids, "LISTMONK_LIST_IDS", "list_ids")
      if list_ids.is_a?(String)
        list_ids = list_ids.split(",").map(&:strip).reject(&:empty?)
      end
      # ensure array
      list_ids = Array(list_ids)

      tags = fetch.call(:tags, "LISTMONK_TAGS", "tags")
      if tags.is_a?(String)
        tags = tags.split(",").map(&:strip).reject(&:empty?)
      end
      tags = Array(tags)

      @config = {
        url: fetch.call(:url, "LISTMONK_URL", "url"),
        user: fetch.call(:user, "LISTMONK_USER", "username"),
        token: fetch.call(:token, "LISTMONK_TOKEN", "token"),
        list_ids: list_ids,
        auth_mode: fetch.call(nil, "LISTMONK_AUTH_MODE", "auth_mode"),
        template_id: fetch.call(:template_id, "LISTMONK_TEMPLATE_ID", "template_id"),
        from_email: fetch.call(:from_email, "LISTMONK_FROM_EMAIL", "from_email"),
        from_name: fetch.call(:from_name, "LISTMONK_FROM_NAME", "from_name"),
        tags: tags,
        subject: fetch.call(:subject, "LISTMONK_SUBJECT", "subject"),
        campaign_name: fetch.call(:campaign_name, "LISTMONK_CAMPAIGN_NAME", "campaign_name"),
        campaign_type: fetch.call(:campaign_type, "LISTMONK_CAMPAIGN_TYPE", "campaign_type") || "regular",
        upload_media: fetch.call(:upload_media, "LISTMONK_UPLOAD_MEDIA", "upload_media") == true,
        format: fetch.call(:format, "LISTMONK_FORMAT", "format"),
        picture_tag_preset: fetch.call(:picture_tag_preset, "LISTMONK_PICTURE_TAG_PRESET", "picture_tag_preset"),
        track_links: fetch.call(:track_links, "LISTMONK_TRACK_LINKS", "track_links") == true,
        include_frontmatter_image: fetch.call(:include_frontmatter_image, "LISTMONK_FRONTMATTER_IMAGE", "frontmatter_image") == true
      }
    end

    def client_from_config
      cfg = resolve_config
      if cfg[:url].to_s.empty?
        cfg[:url] = prompt_for("Listmonk URL")
      end
      if cfg[:user].to_s.empty?
        cfg[:user] = prompt_for("Listmonk Username")
      end
      if cfg[:token].to_s.empty?
        cfg[:token] = prompt_for("Listmonk Token/Password")
      end

      raise "Missing configuration: LISTMONK_URL / listmonk.url" if cfg[:url].to_s.empty?
      raise "Missing configuration: LISTMONK_USER / listmonk.username" if cfg[:user].to_s.empty?
      raise "Missing configuration: LISTMONK_TOKEN / listmonk.token" if cfg[:token].to_s.empty?

      use_token_header = cfg[:auth_mode].to_s.downcase == "header"
      ListmonkClient.new(base_url: cfg[:url], username: cfg[:user], token: cfg[:token], use_token_header: use_token_header)
    end

    def prompt_for(label, default: nil)
      print "#{label}#{default ? " [#{default}]" : ""}: "
      val = $stdin.gets.to_s.strip
      val.empty? ? default : val
    end

    def absolutize_img_srcs(html, site_url:, baseurl:)
      site = site_url.to_s.strip.sub(%r{/\z}, "")
      return html.to_s if site.empty?

      base = baseurl.to_s.strip
      base = "" if base == "/"
      base = "/#{base}" unless base.empty? || base.start_with?("/")
      base = base.sub(%r{/\z}, "")

      html.to_s.gsub(/(<img\b[^>]*\bsrc=)(?:"([^"]+)"|'([^']+)'|([^\s>]+))/i) do
        prefix = Regexp.last_match(1)
        raw = (Regexp.last_match(2) || Regexp.last_match(3) || Regexp.last_match(4) || "").to_s

        # Preserve query/fragment while normalizing the path portion.
        path, frag = raw.split("#", 2)
        path, query = path.split("?", 2)

        if path.empty? || path.start_with?("http://", "https://", "data:", "//")
          %(#{prefix}"#{raw}")
        else
          abs_path = path.start_with?("/") ? path : "#{base}/#{path}"
          abs_path = "/#{abs_path}" unless abs_path.start_with?("/")

          if !base.empty? && !abs_path.start_with?(base + "/") && abs_path != base
            abs_path = base + abs_path
          end

          out = site + abs_path
          out += "?#{query}" if query && !query.empty?
          out += "##{frag}" if frag && !frag.empty?
          %(#{prefix}"#{out}")
        end
      end
    end

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

    def rewrite_html_with_guessed_media_urls!(html, destination_dir, listmonk_url:, baseurl:, site_url:)
      srcs = extract_img_srcs(html)
      warn "No <img src=...> found to rewrite." if srcs.empty?
      return html if srcs.empty?

      baseurl_norm = baseurl.to_s.strip
      baseurl_norm = "" if baseurl_norm == "/"
      baseurl_norm = "/#{baseurl_norm}" unless baseurl_norm.empty? || baseurl_norm.start_with?("/")
      baseurl_norm = baseurl_norm.sub(%r{/\z}, "")

      site_url_norm = site_url.to_s.strip.sub(%r{/\z}, "")
      listmonk_base = listmonk_url.to_s.strip.sub(%r{/\z}, "")

      mapping = {}
      srcs.each do |src|
        next if src.start_with?("data:")

        path =
          if src.start_with?("http://", "https://")
            if !site_url_norm.empty? && (src.start_with?(site_url_norm + "/") || src == site_url_norm)
              src.sub(site_url_norm, "")
            else
              next
            end
          elsif src.start_with?("//")
            next
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

        # Prefer a .jpg/.jpeg variant if we generated one.
        if File.extname(fs_path).downcase == ".png"
          jpg = fs_path.sub(/\.png\z/i, ".jpg")
          jpeg = fs_path.sub(/\.png\z/i, ".jpeg")
          if File.file?(jpg)
            fs_path = jpg
          elsif File.file?(jpeg)
            fs_path = jpeg
          end
        end

        raise "Could not find local file for img src=#{src.inspect} (looked for #{fs_path})" unless File.file?(fs_path)

        next if mapping.key?(src)
        # The final Listmonk media URL does not include the local site path; it uses
        # the uploaded file's name.
        guessed_filename = File.basename(fs_path.to_s)
        guessed = "#{listmonk_base}/uploads/#{guessed_filename}"
        mapping[src] = guessed
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

