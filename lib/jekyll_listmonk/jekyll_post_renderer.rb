module JekyllListmonk
  class JekyllPostRenderer
    class Error < StandardError; end

    def initialize(source_dir: Dir.pwd, jekyll_env: ENV.fetch("JEKYLL_ENV", "production"), picture_tag_preset: nil)
      @source_dir = source_dir
      @jekyll_env = jekyll_env
      @rewriter = PictureTagRewriter.new(preset: picture_tag_preset)
    end

    # identifier can be:
    # - a slug like "instructions-beyond-code"
    # - a post filename stem like "2024-03-07-instructions-beyond-code"
    # - a path like "_posts/2024-03-07-instructions-beyond-code.md"
    def render_post_fragment!(identifier, destination_dir: nil, inject_frontmatter_picture_tag: true,
                              inject_frontmatter_image: false)
      require "jekyll"
      require "liquid"

      previous_jekyll_env = ENV["JEKYLL_ENV"]
      ENV["JEKYLL_ENV"] = @jekyll_env

      config_overrides = { "source" => @source_dir, "quiet" => true }
      config_overrides["destination"] = destination_dir if destination_dir && !destination_dir.to_s.strip.empty?
      site = Jekyll::Site.new(Jekyll.configuration(config_overrides))
      site.reset
      site.read

      doc = resolve_post!(site, identifier)

      original_layout = doc.data["layout"]
      original_content = doc.content

      doc.data["layout"] = nil
      # Liquid's tag registry varies across versions; prefer a tolerant lookup.
      tags = Liquid::Template.tags
      picture_tag_available = !!(tags.respond_to?(:[]) ? tags["picture"] : nil)
      picture_tag_available &&= inject_frontmatter_picture_tag

      frontmatter_image = inject_frontmatter_image ? doc.data["image"] : nil
      doc.content = @rewriter.rewrite(original_content,
                                      frontmatter_image: frontmatter_image,
                                      picture_tag_available: picture_tag_available)

      renderer = Jekyll::Renderer.new(site, doc)
      html = renderer.run.to_s
      html = @rewriter.strip_responsive_img_attributes(html)

      # Append link paragraph if the post has a link field in frontmatter
      if (link = doc.data["link"]) && !link.to_s.strip.empty?
        link_display = link.to_s.sub(%r{\A\w+://}, "")
        html = html.to_s + %(<p>Link: <a href="#{link}">#{link_display}</a></p>)
      end

      doc.data["layout"] = original_layout
      doc.content = original_content

      {
        title: doc.data["title"].to_s,
        html: html,
        destination_dir: site.config["destination"].to_s,
        baseurl: site.config.fetch("baseurl", "").to_s,
        site_url: site.config.fetch("url", "").to_s
      }
    rescue LoadError => e
      raise Error, "Jekyll not available: #{e.message}. Run inside a Jekyll repo with Bundler (bundle exec ...)."
    ensure
      if defined?(previous_jekyll_env)
        if previous_jekyll_env.nil?
          ENV.delete("JEKYLL_ENV")
        else
          ENV["JEKYLL_ENV"] = previous_jekyll_env
        end
      end
    end

    private

    def resolve_post!(site, identifier)
      id = identifier.to_s.strip
      raise Error, "Missing post identifier" if id.empty?

      candidates = site.posts.docs

      if id.include?("/") || id.end_with?(".md", ".markdown")
        normalized = id.sub(%r{\A\./}, "")
        match = candidates.find { |d| d.relative_path == normalized || d.path.end_with?(normalized) }
        return match if match
        raise Error, "No post matched path #{identifier.inspect}"
      end

      matches = candidates.select do |d|
        stem = File.basename(d.path, ".*")
        slug = stem.sub(/^\d{4}-\d{2}-\d{2}-/, "")
        dslug = d.data["slug"].to_s

        id == stem || id == slug || (!dslug.empty? && id == dslug) || stem.include?(id)
      end

      return matches.first if matches.size == 1
      raise Error, "No post matched #{identifier.inspect}" if matches.empty?

      raise Error,
            "Ambiguous identifier #{identifier.inspect}. Matches: #{matches.map { |d| d.relative_path }.join(', ')}"
    end
  end
end

