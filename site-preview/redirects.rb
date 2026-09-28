# frozen_string_literal: true

require "json"
require_relative "support"

module SitePreview
  module Redirects
    def self.load(path)
      return {} unless File.exist?(path)

      mapping = JSON.parse(File.read(path))
      raise ArgumentError, "Redirects must be a JSON object" unless mapping.is_a?(Hash)

      mapping.each do |key, target|
        unless key.is_a?(String) && !key.empty? && target.is_a?(String) && !target.empty?
          raise ArgumentError, "Redirect sources and targets must be nonempty strings"
        end
      end
      mapping
    end

    def self.upload(client, bucket, key, target)
      client.put_object(
        bucket:,
        key:,
        body: target,
        website_redirect_location: target,
        content_type: "text/html;charset=utf-8"
      ).etag
    end
  end
end
