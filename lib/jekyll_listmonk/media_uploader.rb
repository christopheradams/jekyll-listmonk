module JekyllListmonk
  class MediaUploader
    def initialize(client:, destination_dir:, baseurl: "", site_url: "", listmonk_url: "")
      @client = client
      @destination_dir = destination_dir
      @baseurl = normalize_baseurl(baseurl)
      @site_url = normalize_site_url(site_url)
      @listmonk_url = normalize_site_url(listmonk_url)
      @html_processor = HtmlProcessor.new(site_url: site_url, baseurl: baseurl)
    end

    # Uploads images found in HTML to Listmonk and rewrites src attributes
    def rewrite_html_with_uploaded_media!(html)
      srcs = @html_processor.extract_img_srcs(html)
      warn "No <img src=...> found to upload." if srcs.empty?
      return html if srcs.empty?

      mapping = {}
      srcs.each do |src|
        next if src.start_with?("data:")

        fs_path = resolve_local_path(src)
        next unless fs_path

        preferred_path = prefer_jpg_variant(fs_path)
        raise "Could not find local file for img src=#{src.inspect} (looked for #{preferred_path})" unless File.file?(preferred_path)

        next if mapping.key?(src)

        res = @client.upload_media!(preferred_path)
        url = res.dig("data", "url").to_s
        id = res.dig("data", "id")
        raise "Listmonk media upload did not return data.url for #{preferred_path}" if url.empty?

        warn "Uploaded media id=#{id || "(unknown)"} src=#{src} url=#{url}"
        mapping[src] = url
      end

      @html_processor.rewrite_img_srcs(html, mapping)
    end

    # Generates guessed Listmonk URLs for dry-run mode
    def rewrite_html_with_guessed_media_urls!(html)
      srcs = @html_processor.extract_img_srcs(html)
      warn "No <img src=...> found to rewrite." if srcs.empty?
      return html if srcs.empty?

      mapping = {}
      srcs.each do |src|
        next if src.start_with?("data:")

        fs_path = resolve_local_path(src)
        next unless fs_path

        # Prefer a .jpg/.jpeg variant if we generated one
        if File.extname(fs_path).downcase == ".png"
          jpg = fs_path.sub(/\.png\z/i, ".jpg")
          jpeg = fs_path.sub(/\.png\z/i, ".jpeg")
          fs_path = jpg if File.file?(jpg)
          fs_path = jpeg if fs_path.end_with?(".png") && File.file?(jpeg)
        end

        raise "Could not find local file for img src=#{src.inspect} (looked for #{fs_path})" unless File.file?(fs_path)

        next if mapping.key?(src)

        guessed_filename = File.basename(fs_path.to_s)
        guessed = "#{@listmonk_url}/uploads/#{guessed_filename}"
        mapping[src] = guessed
      end

      @html_processor.rewrite_img_srcs(html, mapping)
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

    def resolve_local_path(src)
      # Support both site-relative paths ("/assets/foo.jpg") and absolute URLs
      # that point at this site (e.g., "https://example.com/assets/foo.jpg")
      path =
        if src.start_with?("http://", "https://")
          if !@site_url.empty? && (src.start_with?("#{@site_url}/") || src == @site_url)
            src.sub(@site_url, "")
          else
            return nil
          end
        elsif src.start_with?("//")
          # Protocol-relative URL. Only handle if we can match the configured site URL
          site_no_proto = @site_url.sub(%r{\Ahttps?:}, "")
          if !site_no_proto.empty? && (src.start_with?("#{site_no_proto}/") || src == site_no_proto)
            src.sub(site_no_proto, "")
          else
            return nil
          end
        else
          src.dup
        end

      path = path.split("#", 2).first
      path = path.split("?", 2).first

      if !@baseurl.empty? && path.start_with?("#{@baseurl}/")
        path = path.sub(@baseurl, "")
      elsif path == @baseurl
        return nil
      end

      fs_rel = path.to_s.sub(%r{\A/}, "")
      return nil if fs_rel.empty?

      File.join(@destination_dir.to_s, fs_rel)
    end

    def prefer_jpg_variant(fs_path)
      return fs_path unless File.extname(fs_path).downcase == ".png"

      jpg = fs_path.sub(/\.png\z/i, ".jpg")
      return jpg if File.file?(jpg)

      jpeg = fs_path.sub(/\.png\z/i, ".jpeg")
      return jpeg if File.file?(jpeg)

      fs_path
    end
  end
end
