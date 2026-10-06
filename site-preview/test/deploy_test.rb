# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "tmpdir"
require_relative "../deploy"
require_relative "support/fake_s3"

# Recovery tests verify bucket state across several deployment attempts.
# rubocop:disable-next Minitest/MultipleAssertions
class DeployTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir
    @site = File.join(@root, "site")
    @redirects = File.join(@root, "redirects.json")
    @now = Time.utc(2026, 9, 28)
    @client = FakeS3.new(@now)
    write("index.html", "home")
    write("asset.txt", "first")
    redirects("old.html" => "/first/")
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_cold_and_warm_deploy_compare_content_not_mtime
    assert_equal({ uploaded: 3, skipped: 0, deleted: 0 }, deploy)
    assert_equal %w[asset.txt index.html old.html], JSON.parse(manifest).fetch("objects").keys.sort
    @client.puts.clear
    File.utime(@now + 60, @now + 60, File.join(@site, "asset.txt"))

    assert_equal({ uploaded: 0, skipped: 3, deleted: 0 }, deploy)
    assert_equal [SitePreview::MANIFEST_KEY], @client.puts

    write("asset.txt", "other") # Different content with identical size.
    redirects("old.html" => "/other/")

    assert_equal({ uploaded: 2, skipped: 1, deleted: 0 }, deploy)
    assert_equal "other", object("asset.txt").fetch(:body)
    assert_equal "/other/", object("old.html").fetch(:website_redirect_location)
    assert_equal Digest::SHA256.hexdigest("other"), object("asset.txt").fetch(:metadata).fetch("sha256")
  end

  def test_missing_and_expiring_objects_are_refreshed
    deploy
    @now += SitePreview::REFRESH_AFTER - 1

    assert_equal 0, deploy.fetch(:uploaded)
    @client.objects.delete("asset.txt")

    assert_equal 1, deploy.fetch(:uploaded)
    @now += 1

    assert_equal({ uploaded: 2, skipped: 1, deleted: 0 }, deploy)
    assert_equal @now, object("old.html").fetch(:last_modified)
  end

  def test_remote_replacements_are_repaired
    deploy
    @client.put_object(bucket: "preview", key: "asset.txt", body: "someone else's content")

    assert_equal 1, deploy.fetch(:uploaded)
    assert_equal "first", object("asset.txt").fetch(:body)
  end

  def test_obsolete_keys_are_deleted_in_batches
    deploy
    1001.times do |number|
      @client.put_object(bucket: "preview", key: "stale/#{number}", body: "old")
    end
    File.unlink(File.join(@site, "asset.txt"))
    redirects({})

    assert_equal({ uploaded: 0, skipped: 1, deleted: 1003 }, deploy)
    assert_equal([1000, 3], @client.deletes.map { |batch| batch.fetch(:objects).length })
    assert_equal [SitePreview::MANIFEST_KEY, "index.html"].sort, @client.objects.keys.sort
  end

  def test_delete_failure_does_not_publish_success_and_is_retried
    deploy
    previous = manifest
    File.unlink(File.join(@site, "asset.txt"))
    redirects({})
    @client.fail_deletes << "old.html"
    @client.puts.clear
    assert_raises(RuntimeError) { deploy }
    assert_equal previous, manifest
    refute_includes @client.puts, SitePreview::MANIFEST_KEY
    assert @client.objects.key?("old.html")

    @client.fail_deletes.clear

    assert_equal 1, deploy.fetch(:deleted)
    assert_equal [SitePreview::MANIFEST_KEY, "index.html"].sort, @client.objects.keys.sort
  end

  def test_file_and_redirect_transitions_replace_metadata
    write("old.html", "generated redirect stub")
    deploy

    assert_equal "/first/", object("old.html").fetch(:website_redirect_location)
    redirects({})

    assert_equal 1, deploy.fetch(:uploaded)
    assert_equal "generated redirect stub", object("old.html").fetch(:body)
    refute object("old.html").key?(:website_redirect_location)

    redirects("old.html" => "/second/")

    assert_equal 1, deploy.fetch(:uploaded)
    assert_equal "/second/", object("old.html").fetch(:website_redirect_location)
    refute object("old.html").key?(:metadata)
  end

  def test_failed_upload_then_revert_repairs_files_and_redirects
    deploy
    @client.put_object(bucket: "preview", key: "obsolete", body: "old")
    write("asset.txt", "other")
    redirects("old.html" => "/other/")
    write("broken.txt", "broken")
    @client.fail_puts << "broken.txt"
    assert_raises(RuntimeError) { deploy }
    assert_equal ["index.html"], JSON.parse(manifest).fetch("objects").keys
    assert_equal "other", object("asset.txt").fetch(:body)
    assert_equal "/other/", object("old.html").fetch(:website_redirect_location)
    assert @client.objects.key?("obsolete")

    write("asset.txt", "first")
    redirects("old.html" => "/first/")
    File.unlink(File.join(@site, "broken.txt"))
    @client.fail_puts.clear

    assert_equal({ uploaded: 2, skipped: 1, deleted: 1 }, deploy)
    assert_equal "first", object("asset.txt").fetch(:body)
    assert_equal "/first/", object("old.html").fetch(:website_redirect_location)
  end

  def test_manifest_publication_failure_is_recoverable
    deploy
    write("asset.txt", "other")
    redirects("old.html" => "/other/")
    key = SitePreview::MANIFEST_KEY
    # Permit the checkpoint, then fail publishing the complete manifest.
    @client.fail_nth_puts[key] = @client.put_attempts[key] + 2
    assert_raises(RuntimeError) { deploy }
    assert_equal ["index.html"], JSON.parse(manifest).fetch("objects").keys
    assert_equal "other", object("asset.txt").fetch(:body)
    assert_equal({ uploaded: 2, skipped: 1, deleted: 0 }, deploy)
    assert_equal 0, deploy.fetch(:uploaded)
  end

  def test_checkpoint_failure_prevents_site_changes
    deploy
    previous = manifest
    write("asset.txt", "other")
    redirects({})
    @client.fail_puts << SitePreview::MANIFEST_KEY
    @client.puts.clear
    assert_raises(RuntimeError) { deploy }
    assert_equal previous, manifest
    assert_empty @client.puts
    assert_empty @client.deletes
    assert_equal "first", object("asset.txt").fetch(:body)
    assert @client.objects.key?("old.html")
  end

  def test_failed_identical_body_transition_then_revert_repairs_metadata
    write("old.html", "/first/")
    redirects({})
    deploy
    original_etag = object("old.html").fetch(:etag)
    redirects("old.html" => "/first/")
    write("broken.txt", "broken")
    @client.fail_puts << "broken.txt"
    assert_raises(RuntimeError) { deploy }
    assert_equal original_etag, object("old.html").fetch(:etag)
    assert_equal "/first/", object("old.html").fetch(:website_redirect_location)

    redirects({})
    File.unlink(File.join(@site, "broken.txt"))
    @client.fail_puts.clear

    assert_equal 1, deploy.fetch(:uploaded)
    refute object("old.html").key?(:website_redirect_location)
  end

  def test_uploads_overlap_with_bounded_concurrency
    (SitePreview::WORKERS * 3).times { |number| write("many/#{number}.txt", "content") }
    @client.delay = 0.01
    deploy

    assert_operator @client.peak, :>, 1
    assert_operator @client.peak, :<=, SitePreview::WORKERS
    assert_equal 0, @client.active
    assert_equal SitePreview::MANIFEST_KEY, @client.puts.last
  end

  def test_preserves_mime_types_and_matches_redirect_keys_literally
    types = {
      "index.html" => "text/html;charset=utf-8",
      "js/app.js" => "application/javascript",
      "js/player.mjs" => "application/javascript",
      "css/main.css" => "text/css;charset=utf-8",
      "ai.txt" => "text/plain;charset=utf-8",
      ".well-known/security.txt" => "text/plain;charset=utf-8",
      "site.webmanifest" => "application/manifest+json",
      "rss" => "application/rss+xml",
      "changelog/rss" => "application/rss+xml",
      "img/logo.svg" => "image/svg+xml",
      "unknown.no-known-mime" => "application/octet-stream",
    }
    types.each_key { |key| write(key, "contents") }
    write("old/other.html", "keep this file")
    write("old/*.html", "generated redirect")
    redirects("old/*.html" => "/first/")
    deploy

    types.each { |key, mime| assert_equal mime, object(key).fetch(:content_type), key }
    assert_equal "keep this file", object("old/other.html").fetch(:body)
    assert_equal "/first/", object("old/*.html").fetch(:website_redirect_location)
  end

  def test_invalid_site_fails_before_bucket_changes
    File.unlink(File.join(@site, "index.html"))
    assert_raises(ArgumentError) { deploy }
    assert_empty @client.puts
    assert_empty @client.deletes
  end

  def test_reserved_manifest_path_fails_even_when_redirected
    write(SitePreview::MANIFEST_KEY, "{}")
    assert_raises(ArgumentError) { deploy }
    assert_empty @client.puts
    File.unlink(File.join(@site, SitePreview::MANIFEST_KEY))
    redirects(SitePreview::MANIFEST_KEY => "/first/")
    assert_raises(ArgumentError) { deploy }
    assert_empty @client.puts
  end

  def test_file_symlinks_and_directory_loops_fail_before_upload
    link = File.join(@site, "link")
    [File.join(@site, "index.html"), @site].each do |target|
      File.symlink(target, link)
      assert_raises(ArgumentError) { deploy }
      assert_empty @client.puts
      File.unlink(link)
    end
  end

  private

  def write(key, content)
    path = File.join(@site, key)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  def redirects(mapping)
    File.write(@redirects, JSON.generate(mapping))
  end

  def deploy
    @client.now = @now
    result = nil
    capture_io do
      result = SitePreview::Deploy.new(
        client: @client, bucket: "preview", directory: @site,
        redirects_path: @redirects, now: @now
      ).run
    end
    result
  end

  def object(key)
    @client.objects.fetch(key)
  end

  def manifest
    object(SitePreview::MANIFEST_KEY).fetch(:body)
  end
end
