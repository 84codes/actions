# frozen_string_literal: true

require_relative "redirects"

begin
  redirects = SitePreview::Redirects.load(ENV.fetch("REDIRECTS_FILE", "redirects.json"))
  unless redirects.empty?
    client = SitePreview.client
    bucket = ENV.fetch("BUCKET")
    SitePreview.parallel_each(redirects) do |key, target|
      SitePreview::Redirects.upload(client, bucket, key, target)
      puts "Redirect: #{key} -> #{target}"
    end
  end
  puts "Applied #{redirects.size} redirects"
rescue StandardError => e
  warn "Redirect deployment failed: #{e.message}"
  exit 1
end
