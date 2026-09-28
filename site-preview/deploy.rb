# frozen_string_literal: true

require_relative "redirects"
require_relative "site_files"

module SitePreview
  class Deploy
    def initialize(client:, bucket:, directory:, redirects_path:, now: Time.now)
      @client = client
      @bucket = bucket
      @directory = directory
      @redirects_path = redirects_path
      @now = now
    end

    def run
      # Validate and hash the complete build before changing anything in S3.
      redirects = Redirects.load(@redirects_path)
      expected = SiteFiles.plan(@directory, redirects)
      redirects.each do |key, target|
        expected[key] = { "kind" => "redirect", "target" => target,
                          "content_type" => "text/html;charset=utf-8" }
      end
      previous = load_manifest
      remote = list_objects
      manifest = {}
      pending = {}
      expected.each do |key, record|
        if unchanged?(record, previous[key], remote[key])
          manifest[key] = record.merge("etag" => remote.fetch(key).etag)
        else
          pending[key] = record
        end
      end

      skipped = manifest.size
      puts "Deploying #{pending.size} objects; skipping #{skipped} unchanged objects"
      # Forget keys about to change before uploading. Identical object bytes
      # can still need different metadata after a failed deploy and rollback.
      save_manifest(manifest) unless pending.empty?
      upload_objects(pending, manifest)
      obsolete = remote.keys - expected.keys - [MANIFEST_KEY]
      delete_objects(obsolete)
      save_manifest(manifest)
      summary = { uploaded: pending.size, skipped:, deleted: obsolete.size }
      puts "Deployment complete: #{summary.map { |key, value| "#{key}=#{value}" }.join(', ')}"
      summary
    end

    private

    def load_manifest
      body = @client.get_object(bucket: @bucket, key: MANIFEST_KEY).body
      manifest = JSON.parse(body.read)
      unless manifest.is_a?(Hash) && manifest["version"] == 1 && manifest["objects"].is_a?(Hash)
        raise ArgumentError, "Unsupported or invalid site-preview manifest"
      end

      manifest.fetch("objects")
    rescue Aws::S3::Errors::NoSuchKey, Aws::S3::Errors::NotFound
      {}
    ensure
      body&.close
    end

    def save_manifest(objects)
      @client.put_object(
        bucket: @bucket, key: MANIFEST_KEY,
        body: JSON.generate("version" => 1, "objects" => objects.sort.to_h),
        content_type: "application/json", cache_control: "no-store"
      )
    end

    def list_objects
      objects = {}
      @client.list_objects_v2(bucket: @bucket).each do |page|
        page.contents.each { |object| objects[object.key] = object }
      end
      objects
    end

    def unchanged?(expected, previous, remote)
      previous.is_a?(Hash) && remote &&
        expected.all? { |key, value| previous[key] == value } &&
        previous["etag"] == remote.etag && @now - remote.last_modified < REFRESH_AFTER
    end

    def upload_objects(pending, manifest)
      mutex = Mutex.new
      SitePreview.parallel_each(pending) do |key, record|
        etag = if record.fetch("kind") == "redirect"
                 Redirects.upload(@client, @bucket, key, record.fetch("target"))
               else
                 SiteFiles.upload(@client, @bucket, key, record, @directory)
               end
        mutex.synchronize do
          manifest[key] = record.merge("etag" => etag)
          puts "Uploaded: #{key}"
        end
      end
    end

    def delete_objects(keys)
      keys.each_slice(1000) do |batch|
        response = @client.delete_objects(
          bucket: @bucket, delete: { objects: batch.map { |key| { key: } }, quiet: true }
        )
        raise "Failed to delete obsolete objects: #{response.errors.inspect}" unless response.errors.empty?
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    SitePreview::Deploy.new(
      client: SitePreview.client,
      bucket: ENV.fetch("BUCKET"),
      directory: ENV.fetch("SITE_DIR", "_site"),
      redirects_path: ENV.fetch("REDIRECTS_FILE", "redirects.json")
    ).run
  rescue StandardError => e
    warn "Deployment failed: #{e.message}"
    exit 1
  end
end
