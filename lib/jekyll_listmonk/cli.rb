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
        run_lists_command
      when "campaign"
        run_campaign_command
      when "upload"
        run_upload_command
      else
        raise "Unknown command: #{cmd.inspect} (expected campaign|upload)"
      end
    end

    private

    def run_lists_command
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
    end

    def run_campaign_command
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

      if cmd_config[:format] && !Constants::VALID_FORMATS.include?(cmd_config[:format])
        raise "Invalid --format #{cmd_config[:format].inspect} (expected html|markdown)"
      end

      # Merge command-specific config into global options for resolution
      @cmd_config = cmd_config
      cfg = resolve_config

      post = @argv.shift
      raise "Missing post identifier" if post.nil? || post.empty?

      # Load params from config
      upload_media = cfg[:upload_media]
      format = cfg[:format] || Constants::CONTENT_TYPE_HTML
      picture_tag_preset = cfg[:picture_tag_preset]
      track_links = cfg[:track_links]
      include_frontmatter_image = cfg[:include_frontmatter_image]

      # Ignore picture_tag_preset if not uploading media, because we can't depend on the
      # specific image derivative existing in the build unless we are building into a temp dir
      # and checking file existence (which upload_media does).
      if picture_tag_preset && !upload_media
        warn "Warning: --picture-tag-preset is ignored when --upload-media is not set."
        picture_tag_preset = nil
      end

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

          html_processor = HtmlProcessor.new(site_url: rendered[:site_url].to_s, baseurl: rendered[:baseurl].to_s)
          html = html_processor.absolutize_img_srcs(html)
          html = html_processor.absolutize_hrefs(html)

          if dry_run
            uploader = MediaUploader.new(
              client: nil,
              destination_dir: dest,
              baseurl: rendered[:baseurl].to_s,
              site_url: rendered[:site_url].to_s,
              listmonk_url: resolve_config[:url]
            )
            html = uploader.rewrite_html_with_guessed_media_urls!(html)
          else
            client = client_from_config
            uploader = MediaUploader.new(
              client: client,
              destination_dir: dest,
              baseurl: rendered[:baseurl].to_s,
              site_url: rendered[:site_url].to_s
            )
            html = uploader.rewrite_html_with_uploaded_media!(html)
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

        html_processor = HtmlProcessor.new(site_url: rendered[:site_url].to_s, baseurl: rendered[:baseurl].to_s)
        html = html_processor.absolutize_img_srcs(html)
        html = html_processor.absolutize_hrefs(html)
      end

      if track_links
        html_processor = HtmlProcessor.new
        html = html_processor.rewrite_href_track_link(html)
      end

      content_type = Constants::CONTENT_TYPE_HTML
      body = html
      if format == Constants::CONTENT_TYPE_MARKDOWN
        content_type = Constants::CONTENT_TYPE_MARKDOWN
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
    end

    def run_upload_command
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
    end

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
        campaign_type: fetch.call(:campaign_type, "LISTMONK_CAMPAIGN_TYPE", "campaign_type") || Constants::CAMPAIGN_TYPE_REGULAR,
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
