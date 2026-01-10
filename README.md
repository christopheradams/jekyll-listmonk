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

Create a campaign and inject the post's frontmatter `image` at the top:

```sh
LISTMONK_URL="https://list.example.com" \
LISTMONK_USER="api_user" \
LISTMONK_TOKEN="api_token" \
LISTMONK_LIST_IDS="1" \
bundle exec jekyll-listmonk campaign --frontmatter-image 2025-12-19-white-fungus-issue-18-dino
```

Dry run (render and print the campaign body without uploading media or creating a campaign):

```sh
bundle exec jekyll-listmonk campaign --dry-run 2025-12-19-white-fungus-issue-18-dino
```

If you run `--dry-run` together with `--upload-media`, no uploads happen, but `<img src>` URLs are rewritten
to a guessed location so you can preview the final body shape:

- `LISTMONK_URL + "/upload/" + image_path`

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

### Campaign CLI flags

- `--picture-tag-preset PRESET`: rewrites `{% picture %}` tags to use this preset. If omitted, does not add/override presets (so Jekyll Picture Tag uses the site's default).
- `--track-links`: appends `@TrackLink` to eligible `<a href="...">` URLs in the final HTML (useful for Listmonk link tracking).
- `--frontmatter-image`: injects the post frontmatter `image` at the top of the body.
- `--upload-media`: uploads referenced images to Listmonk media and rewrites `<img src>` to the returned `data.url`.
- `--format html|markdown`: sets the campaign `content_type` and body format.
- `--dry-run`: prints the final body and does not call Listmonk APIs.

## Image behavior

- The post frontmatter `image` is only injected when `campaign --frontmatter-image` is set.
- If the frontmatter image is injected and you're using `campaign --upload-media`, a
  `{% picture ... %}` tag is injected as the first line of content (when the Liquid `picture` tag is available).
- If the frontmatter image is injected and `--upload-media` is not used, it is injected as a Markdown image (`![alt](url)`)
  so the email does not depend on picture-tag-generated derivatives existing in the site build.
- If the site does not have the Liquid `picture` tag available (for example, it is not using
  `jekyll_picture_tag`), the injected frontmatter image falls back to a Markdown image (`![alt](url)`).
- If the post already starts with the same image (either a `{% picture %}` block or a Markdown image),
  the frontmatter image is not injected again (to avoid duplicates).
- In-body `{% picture ... %}` tags have `--img class="..."` removed, and if
  `--picture-tag-preset` is provided, they are rewritten to use that preset.
- Any resulting `srcset`/`sizes` attributes are stripped from `<img>` tags in the output.

If you pass `--picture-tag-preset`, the target site must define that preset in `_data/picture.yml`.

