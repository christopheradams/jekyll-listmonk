require_relative "lib/jekyll_listmonk/version"

Gem::Specification.new do |spec|
  spec.name = "jekyll_listmonk"
  spec.version = JekyllListmonk::VERSION
  spec.authors = ["Christopher Adams"]
  spec.email = ["info@christopheradams.io"]

  spec.summary = "Create listmonk campaigns from Jekyll posts."
  spec.description = "A small CLI that renders a Jekyll post (Liquid + Markdown) and creates a listmonk campaign."
  spec.homepage = "https://github.com/christopheradams/jekyll-listmonk"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0"

  spec.files = Dir[
    "lib/**/*.rb",
    "exe/*",
    "README.md",
    "LICENSE.txt"
  ]

  spec.bindir = "exe"
  spec.executables = ["jekyll-listmonk"]
  spec.require_paths = ["lib"]

  # Jekyll is required at runtime; this tool is intended to be run inside a target
  # Jekyll site's Bundler environment so the site's plugins are available too.
  spec.add_dependency "jekyll", ">= 4.0", "< 5.0"
  spec.add_dependency "nokogiri", ">= 1.13"
  spec.add_dependency "reverse_markdown", ">= 2.1"
end
