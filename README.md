# jekyll_listmonk

Create listmonk campaigns from Jekyll posts.

This is designed to run **inside a target Jekyll site's Bundler environment** so the
site's plugins (for example `jekyll_picture_tag`) are available.

## Install (in a target Jekyll repo)

Add to the site's `Gemfile`:

```ruby
group :development do
  gem "jekyll_listmonk", github: "christopheradams/jekyll-listmonk"
end
```

Then:

```sh
bundle install
```

## Usage

Run these commands from inside your Jekyll site repo (so the site's Bundler environment and plugins
are available).

Preview rendered HTML:

```sh
bundle exec jekyll-listmonk preview 2025-12-19-white-fungus-issue-18-dino
```

Upload a media file to Listmonk:

```sh
LISTMONK_URL="https://list.example.com" \
LISTMONK_USER="api_user" \
LISTMONK_TOKEN="api_token" \
bundle exec jekyll-listmonk upload /path/to/image.jpg
```

Create a campaign:

```sh
LISTMONK_URL="https://list.example.com" \
LISTMONK_USER="api_user" \
LISTMONK_TOKEN="api_token" \
LISTMONK_LIST_IDS="1" \
bundle exec jekyll-listmonk campaign 2025-12-19-white-fungus-issue-18-dino
```

Create a campaign using Markdown instead of HTML:

```sh
LISTMONK_URL="https://list.example.com" \
LISTMONK_USER="api_user" \
LISTMONK_TOKEN="api_token" \
LISTMONK_LIST_IDS="1" \
bundle exec jekyll-listmonk campaign --format markdown 2025-12-19-white-fungus-issue-18-dino
```

Create a campaign and upload referenced images to Listmonk media (rewriting `<img src>` URLs in the HTML):

```sh
LISTMONK_URL="https://list.example.com" \
LISTMONK_USER="api_user" \
LISTMONK_TOKEN="api_token" \
LISTMONK_LIST_IDS="1" \
bundle exec jekyll-listmonk campaign --upload-media 2025-12-19-white-fungus-issue-18-dino
```

### Environment variables

Required:

- `LISTMONK_URL`
- `LISTMONK_USER`
- `LISTMONK_TOKEN`
- `LISTMONK_LIST_IDS` (comma-separated)

Optional:

- `LISTMONK_AUTH_MODE=header` (send `Authorization: token user:token` instead of Basic auth)
- `LISTMONK_TEMPLATE_ID`
- `LISTMONK_SUBJECT` (defaults to post title)
- `LISTMONK_CAMPAIGN_NAME` (defaults to post title)
- `LISTMONK_CAMPAIGN_TYPE` (defaults to `regular`)
- `LISTMONK_FROM_EMAIL`, `LISTMONK_FROM_NAME`
- `LISTMONK_TAGS` (comma-separated)
- `DRY_RUN=1` (prints HTML and does not call the API)

### Jekyll-related CLI flags

- `--picture-tag-preset PRESET`: rewrites `{% picture %}` tags to use this preset. If omitted, does not add/override presets (so Jekyll Picture Tag uses the site's default).
- `--track_links`: appends `@TrackLink` to eligible `<a href="...">` URLs in the final HTML (useful for Listmonk link tracking).

## Image behavior

- If a post's front matter has an `image` field, a `{% picture ... %}` tag is injected as
  the first line of content.
- If the site does not have the Liquid `picture` tag available (for example, it is not using
  `jekyll_picture_tag`), the injected frontmatter image falls back to a Markdown image (`![alt](url)`).
- In-body `{% picture ... %}` tags have `--img class="..."` removed, and if
  `--picture-tag-preset` is provided, they are rewritten to use that preset.
- Any resulting `srcset`/`sizes` attributes are stripped from `<img>` tags in the output.

If you pass `--picture-tag-preset`, the target site must define that preset in `_data/picture.yml`.

