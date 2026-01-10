**WARNING: this package is EXPERIMENTAL and not recommended for
production.**

# jekyll_listmonk

Create Listmonk campaigns from Jekyll posts.

This gem renders a Jekyll post to HTML and creates a campaign in Listmonk. It can also upload local images found in the post to Listmonk's media library and update the image URLs in the HTML.

It runs within your Jekyll site's environment. It has specific support for `jekyll_picture_tag` to help generate email-compatible image markup.

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

Configuration is loaded in this order of precedence:
1. **CLI Flags** (e.g., `--url`, `--lists`)
2. **Environment Variables** (e.g., `LISTMONK_URL`, `LISTMONK_LIST_IDS`)
3. **`_config.yml`** (under `listmonk:` key)

**Recommendation:**

*   **Secrets** (Username, Token): Use **Environment Variables** (via `.env` or shell export).
*   **Defaults** (URL, Lists, From Email): Use **`_config.yml`**.

#### 1. _config.yml (Defaults)

```yaml
listmonk:
  url: "https://list.example.com"
  list_ids: [1]
  from_email: "me@example.com"
  from_name: "My Newsletter"
  # Other options: template_id, tags (array), campaign_type
```

#### 2. Environment Variables (Secrets)

Do not commit these to git. Use a `.env` file (gitignored) or export them in your shell.

```env
LISTMONK_USER=api_user
LISTMONK_TOKEN=api_token
```

Supported variables: `LISTMONK_URL`, `LISTMONK_USER`, `LISTMONK_TOKEN`, `LISTMONK_LIST_IDS`, `LISTMONK_FROM_EMAIL`, `LISTMONK_FROM_NAME`, `LISTMONK_TEMPLATE_ID`, `LISTMONK_TAGS`, `LISTMONK_SUBJECT`, `LISTMONK_CAMPAIGN_NAME`, `LISTMONK_CAMPAIGN_TYPE`, `LISTMONK_AUTH_MODE`.

### Commands

**Global Flags:**

All commands support these flags to override config/env:
- `--url URL`
- `--user USER`
- `--token TOKEN`
- `--dry-run`: Don't call API

**1. Check available lists**

```sh
bundle exec jekyll-listmonk lists
```

**2. Create a campaign**

```sh
bundle exec jekyll-listmonk campaign <POST_ID_OR_SLUG> [options]
```

Options:
- `--lists 1,2`: Comma-separated list IDs
- `--subject "..."`: Override subject (default: post title)
- `--name "..."`: Override campaign name
- `--from-email "..."` / `--from-name "..."`
- `--tags "tag1,tag2"`
- `--template-id 123`
- `--test-email EMAIL`: Send a test email immediately
- `--track-links`: Append `@TrackLink` to URLs
- `--upload-media`: Upload images to Listmonk
- `--frontmatter-image`: Inject frontmatter image
- `--picture-tag-preset PRESET`: Use specific picture tag preset
- `--format html|markdown`: Output format (default: html)

**3. Upload a media file**

```sh
bundle exec jekyll-listmonk upload /path/to/image.jpg
```

### Example Workflow

1.  **Configure defaults** in `_config.yml`:
    ```yaml
    listmonk:
      url: "https://newsletter.mysite.com"
      list_ids: [5]
    ```

2.  **Set secrets** in `.env`:
    ```env
    LISTMONK_USER=admin
    LISTMONK_TOKEN=my-secret-token
    ```

3.  **Run:**
    ```sh
    bundle exec jekyll-listmonk campaign my-latest-post
    ```

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
