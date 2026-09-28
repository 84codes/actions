# frozen_string_literal: true

require "digest"
require "find"
require "mime/types"
require "pathname"
require_relative "support"

module SitePreview
  module SiteFiles
    def self.content_type(key)
      case File.extname(key).downcase
      when ".html", ".htm" then "text/html;charset=utf-8"
      when ".js", ".mjs" then "application/javascript"
      when ".rss" then "application/rss+xml"
      else
        return "application/rss+xml" if %w[rss changelog/rss].include?(key)

        MIME::Types.type_for(key).first&.content_type || "application/octet-stream"
      end
    end

    def self.plan(directory, redirect_keys)
      directory = Pathname.new(directory)
      validate_directory(directory)
      files = {}
      Find.find(directory.to_s, ignore_error: false) do |name|
        path = Pathname.new(name)
        raise ArgumentError, "Site symlinks are not supported: #{path}" if path.symlink?
        next if path.directory?

        key = path.relative_path_from(directory).to_s
        raise ArgumentError, "Site contains reserved key: #{key}" if key == MANIFEST_KEY
        next if redirect_keys.include?(key)
        raise ArgumentError, "Site entry is not a regular file: #{path}" unless path.file?

        files[key] = { "kind" => "file", "sha256" => Digest::SHA256.file(path).hexdigest,
                       "content_type" => content_type(key) }
      end
      files
    end

    def self.validate_directory(directory)
      unless directory.directory? && !directory.symlink?
        raise ArgumentError, "Site directory must be a real directory: #{directory}"
      end
      raise ArgumentError, "Missing index.html in #{directory}" unless directory.join("index.html").file?
    end

    def self.upload(client, bucket, key, record, directory)
      File.open(File.join(directory, key), "rb") do |body|
        client.put_object(
          bucket:, key:, body:,
          content_type: record.fetch("content_type"),
          metadata: { "sha256" => record.fetch("sha256") }
        ).etag
      end
    end
  end
end
