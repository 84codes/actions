# frozen_string_literal: true

require "aws-sdk-s3"

module SitePreview
  WORKERS = 8
  MANIFEST_KEY = "_site-preview/manifest.json"
  # Refresh on deployment before the bucket's 30-day object expiration.
  REFRESH_AFTER = 20 * 24 * 60 * 60

  def self.client
    Aws::S3::Client.new(retry_mode: "standard", max_attempts: 5)
  end

  def self.parallel_each(items)
    queue = Queue.new
    items.each { |item| queue << item }
    queue.close
    errors = Queue.new
    workers = Array.new([WORKERS, queue.size].min) do
      Thread.new do
        while (item = queue.pop)
          yield item
        end
      rescue StandardError => e
        errors << e
      end
    end
    workers.each(&:join)
    raise errors.pop unless errors.empty?
  end
end
