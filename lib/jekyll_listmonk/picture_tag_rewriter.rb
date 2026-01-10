module JekyllListmonk
  class PictureTagRewriter
    def initialize(preset: nil)
      @preset = preset&.to_s&.strip
      @preset = nil if @preset.nil? || @preset.empty?
    end

    def rewrite(markdown, frontmatter_image:, picture_tag_available: true)
      content = markdown.to_s
      content = inject_frontmatter_image(content, frontmatter_image, picture_tag_available: picture_tag_available)
      rewrite_picture_tags_for_newsletter(content)
    end

    def strip_responsive_img_attributes(html)
      html.to_s
        .gsub(/\s+srcset=(\"[^\"]*\"|'[^']*')/, "")
        .gsub(/\s+sizes=(\"[^\"]*\"|'[^']*')/, "")
    end

    private

    def rewrite_picture_tags_for_newsletter(markdown)
      out = +""
      lines = markdown.to_s.lines

      i = 0
      while i < lines.length
        line = lines[i]

        if line.lstrip.start_with?("{% picture")
          tag = +""
          loop do
            tag << lines[i]
            i += 1
            break if tag.include?("%}") || i >= lines.length
          end

          out << transform_picture_tag(tag)
          next
        end

        out << line
        i += 1
      end

      out
    end

    def transform_picture_tag(tag)
      require "shellwords"

      m = tag.match(/\A(\s*)\{\%\s*picture\s+([\s\S]*?)\s*\%\}(\s*)\z/)
      return tag unless m

      leading_ws = m[1]
      inner = m[2]
      trailing_ws = m[3]

      tokens = Shellwords.shellsplit(inner)

      # Split positional args (preset/path) from options (starting at first --flag).
      opt_index = tokens.index { |t| t.start_with?("--") }
      positional = opt_index ? tokens[0...opt_index] : tokens.dup
      options = opt_index ? tokens[opt_index..] : []

      # If a preset is configured, enforce it:
      # - 1 positional arg => it's a path; insert preset before it.
      # - 2+ positional args => assume first is preset; replace it.
      #
      # If no preset is configured, do not add or override a preset (so
      # `{% picture path %}` uses the site's default preset).
      if positional.empty?
        # Unusual/invalid tag; leave unchanged.
        return tag
      end

      if @preset
        if positional.length == 1
          positional = [@preset, positional[0]]
        elsif positional.length >= 2
          positional[0] = @preset
        end
      end

      # Remove `--img class="..."` (and single-quote variant), which appears as:
      #   --img class="foo"
      # i.e., two tokens.
      cleaned_options = []
      i = 0
      while i < options.length
        if options[i] == "--img" && options[i + 1]&.start_with?("class=")
          i += 2
          next
        end
        cleaned_options << options[i]
        i += 1
      end

      normalized_inner = Shellwords.join(positional + cleaned_options)
      "#{leading_ws}{% picture #{normalized_inner} %}#{trailing_ws}"
    rescue ArgumentError
      # Shellwords failed (usually due to unbalanced quotes); fall back to no-op.
      tag
    end

    def inject_frontmatter_image(markdown, image_field, picture_tag_available:)
      content = markdown.to_s

      image_path, image_alt = extract_frontmatter_image(image_field)
      return content if image_path.nil? || image_path.to_s.strip.empty?

      image_path = normalize_image_path(image_path)

      injected =
        if picture_tag_available
          tag = +"{% picture #{image_path}"
          if image_alt && !image_alt.to_s.strip.empty?
            tag << %( --alt "#{escape_liquid_double_quotes(one_line(image_alt))}")
          end
          tag << " %}\n"

          first_picture = first_picture_block(content)
          return content if first_picture && first_picture.include?(image_path)

          tag
        else
          first_img = first_markdown_image_line(content)
          return content if first_img && first_img.include?(image_path)

          alt = image_alt && !image_alt.to_s.strip.empty? ? escape_markdown_alt(one_line(image_alt)) : ""
          url = escape_markdown_url(image_path)
          "![#{alt}](#{url})\n"
        end

      injected + "\n" + content
    end

    def first_picture_block(markdown)
      lines = markdown.to_s.lines
      i = 0
      while i < lines.length
        line = lines[i]
        if line.strip.empty?
          i += 1
          next
        end

        return nil unless line.lstrip.start_with?("{% picture")

        block = +""
        loop do
          block << lines[i]
          i += 1
          break if block.include?("%}") || i >= lines.length
        end
        return block
      end
      nil
    end

    def first_markdown_image_line(markdown)
      lines = markdown.to_s.lines
      lines.each do |line|
        next if line.strip.empty?
        return line if line.lstrip.start_with?("![")
        return nil
      end
      nil
    end

    def extract_frontmatter_image(image_field)
      case image_field
      when String
        [image_field, nil]
      when Hash
        path = image_field["path"] || image_field[:path]
        title = image_field["title"] || image_field[:title]
        [path, title]
      else
        [nil, nil]
      end
    end

    def normalize_image_path(path)
      p = path.to_s.strip
      return p if p.empty?
      p = "/#{p}" unless p.start_with?("/", "./", "../")
      p
    end

    def one_line(s)
      s.to_s.gsub(/\s+/, " ").strip
    end

    def escape_liquid_double_quotes(s)
      s.to_s.gsub("\\", "\\\\").gsub('"', '\"')
    end

    def escape_markdown_alt(s)
      s.to_s
        .gsub("\\", "\\\\")
        .gsub("]", "\\]")
    end

    def escape_markdown_url(s)
      s.to_s
        .gsub(" ", "%20")
        .gsub("(", "\\(")
        .gsub(")", "\\)")
    end
  end
end

