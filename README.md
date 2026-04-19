**Note:** This package is in early development. The API may change between versions.

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
  from_email: "me@example.com" # optional
  from_name: "My Newsletter" # optional
  # [CAMPAIGN OPTIONS]
  # template_id: 1
  # tags: ["tag1", "tag2"]
  # campaign_type: "regular"
  # format: "html"
  # [FEATURE FLAGS]
  # upload_media: true
  # track_links: true
  # frontmatter_image: true
  # picture_tag_preset: "listmonk"
```

#### 2. Environment Variables

**Note**: Do not add the API user or token variables to your Jekyll
config and don't commit them to git. Export them in your shell or use a
`.env` file (see below)

```env
LISTMONK_USER=api_user
LISTMONK_TOKEN=api_token
```

Supported environment variables: `LISTMONK_AUTH_MODE`,
`LISTMONK_CAMPAIGN_NAME`, `LISTMONK_CAMPAIGN_TYPE`, `LISTMONK_DEBUG`,
`LISTMONK_FORMAT`, `LISTMONK_FROM_EMAIL`, `LISTMONK_FROM_NAME`,
`LISTMONK_FRONTMATTER_IMAGE`, `LISTMONK_LIST_IDS`,
`LISTMONK_PICTURE_TAG_PRESET`, `LISTMONK_SUBJECT`, `LISTMONK_TAGS`,
`LISTMONK_TEMPLATE_ID`, `LISTMONK_TOKEN`, `LISTMONK_TRACK_LINKS`,
`LISTMONK_UPLOAD_MEDIA`, `LISTMONK_URL`, `LISTMONK_USER`

##### dotenv

Add the environment variables to a `.env` file, and list in that file in
`.gitignore`. Jekyll excludes dotfiles from the site build by
default. Add the `dotenv` gem to your site's `Gemfile`:

```ruby
# Gemfile
group :development do
  gem "dotenv"
end
```

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
- `--upload-media`: Upload images in the post to Listmonk, and link them in the campaign email
- `--frontmatter-image`: Inject frontmatter image at beginning of the canpaign email 
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

To ensure emails render correctly across clients, this gem automatically:

1.  **Injects Frontmatter Image**: If you use `--frontmatter-image`, the image defined in the post's frontmatter is added to the top of the email.
    *   *Smart check*: It won't be added if the post already starts with that same image.
    *   *Fallback*: Uses a standard Markdown image if `jekyll_picture_tag` isn't available.

2.  **Optimizes `{% picture %}` Tags**:
    *   **Strips Classes**: Removes CSS classes (like `--img class="..."`) that might break email layouts.
    *   **Enforces Preset**: If you provide `--picture-tag-preset` (and `--upload-media` is on), all picture tags are rewritten to use it (ensuring consistent sizing/formatting).
    *   **Cleans Output**: Strips `srcset` and `sizes` attributes from the final HTML `<img>` tags, as these are poorly supported in email clients.

### Recommended Picture Preset

If you use `jekyll_picture_tag`, add a dedicated "listmonk" preset to your `_data/picture.yml`. This ensures images are generated at a fixed width suitable for email.

```yaml
# _data/picture.yml
presets:
  listmonk:
    formats: [jpg]
    widths: [640]
    fallback_width: 640
    markup: img
```

Then configure it in `_config.yml`:

```yaml
listmonk:
  picture_tag_preset: "listmonk"
```
