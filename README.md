**WARNING: this package is EXPERIMENTAL and not recommended for
production.**

# jekyll_listmonk

Create listmonk campaigns from Jekyll posts.

This gem helps you turn your Jekyll posts into beautiful newsletters by handling the heavy lifting of converting your site's content and assets for email compatibility.

It runs within your existing Jekyll environment, meaning it automatically works with your site's plugins (like `jekyll_picture_tag`) to ensure your images and content look exactly how you expect.

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

Run these commands from inside your Jekyll site repo (so the site's Bundler environment and plugins are available).

### Configuration

You can configure Listmonk settings in your `_config.yml` (easiest for non-sensitive data) or via environment variables/`.env` file (recommended for secrets).

**1. `_config.yml` (Non-sensitive defaults)**

Add this to `_config.yml`:

```yaml
listmonk:
  url: "https://list.example.com"
  list_ids: [1] # Default list IDs
  from_email: "me@example.com" # Optional
  from_name: "My Newsletter"   # Optional
```

**2. Credentials (Secure)**

**Do not commit your username or password to `_config.yml`.** Instead, provide them via environment variables.

You can create a `.env` file in your project root (ensure it is in your `.gitignore`):

```env
# .env
LISTMONK_USER=api_user
LISTMONK_TOKEN=api_token
```

Then add `gem "dotenv"` to your `Gemfile` (group `:development` is fine) and run `bundle install`. `jekyll-listmonk` will automatically load variables from `.env`.

Alternatively, export them in your shell:

```sh
export LISTMONK_USER="api_user"
export LISTMONK_TOKEN="api_token"
```

If required settings are missing, the CLI will prompt you for them interactively.

### Commands

**1. Check available lists**

```sh
bundle exec jekyll-listmonk lists
```

**2. Create a campaign**

```sh
bundle exec jekyll-listmonk campaign 2025-12-19-white-fungus-issue-18-dino
```

**3. Send a test email**

Create a campaign and immediately send a test email to check rendering:

```sh
bundle exec jekyll-listmonk campaign my-post --test-email me@example.com
```

**4. Upload a media file**

```sh
bundle exec jekyll-listmonk upload /path/to/image.jpg
```

### Campaign CLI flags

- `--test-email EMAIL`: Sends a test email to this address for the created campaign.
- `--picture-tag-preset PRESET`: rewrites `{% picture %}` tags to use this preset. If omitted, does not add/override presets (so Jekyll Picture Tag uses the site's default).
- `--track-links`: appends `@TrackLink` to eligible `<a href="...">` URLs in the final HTML (useful for Listmonk link tracking).
- `--frontmatter-image`: injects the post frontmatter `image` at the top of the body.
- `--upload-media`: uploads referenced images to Listmonk media and rewrites `<img src>` to the returned `data.url`.
- `--format html|markdown`: sets the campaign `content_type` and body format.
- `--dry-run`: prints the final body and does not call Listmonk APIs. If used together with `--upload-media`, no uploads happen but `<img src>` URLs are rewritten to a guessed location: `LISTMONK_URL + "/uploads/" + image_filename`.

### Environment variables (Reference)

Most of these can be set in `_config.yml` under the `listmonk:` key.

Required:
- `LISTMONK_URL`
- `LISTMONK_USER`
- `LISTMONK_TOKEN`

Optional:
- `LISTMONK_LIST_IDS`
- `LISTMONK_AUTH_MODE=header` (send `Authorization: token user:token` instead of Basic auth)
- `LISTMONK_TEMPLATE_ID`
- `LISTMONK_SUBJECT` (defaults to post title)
- `LISTMONK_CAMPAIGN_NAME` (defaults to post title)
- `LISTMONK_CAMPAIGN_TYPE` (defaults to `regular`)
- `LISTMONK_FROM_EMAIL`, `LISTMONK_FROM_NAME`
- `LISTMONK_TAGS` (comma-separated)

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

### Recommended picture preset

Install `jekyll_picture_tag` with your jekyll plugins.

Add this preset to `_data/picture.yml`, and call the campaign command
with the option `--picture-tag-preset newsletter`.

```
# _data/picture.yml
presets:
  newsletter:
    formats: [jpg]
    widths: [640]
    fallback_width: 640
    markup: img
``
