# frozen_string_literal: true

require "aws-sdk-s3"
require "digest"
require "json"
require "minitest/autorun"
require "pathname"
require "tempfile"
require "timeout"
require "tmpdir"

require_relative "../redirects"
require_relative "../support"

class RedirectsTest < Minitest::Test
  def with_redirects(contents)
    Tempfile.create(["redirects", ".json"]) do |file|
      file.write(contents)
      file.flush
      yield Pathname(file.path)
    end
  end

  def test_loads_missing_and_empty_mappings
    Dir.mktmpdir do |directory|
      assert_empty SitePreview::Redirects.load(Pathname(directory).join("missing.json"))
    end
    with_redirects("{}\n") do |path|
      assert_empty SitePreview::Redirects.load(path)
    end
  end

  def test_validates_all_entries_before_uploading
    invalid_inputs = [
      "not json", "", "[]", "null",
      { "" => "/target/" },
      { "old.html" => "" },
      { "old.html" => nil },
      { "old.html" => ["/target/"] },
      { "old.html" => 123 }
    ]
    invalid_inputs.each do |input|
      contents = input.is_a?(String) ? input : JSON.generate(input)

      with_redirects(contents) do |path|
        assert_raises(ArgumentError, JSON::ParserError, contents) do
          SitePreview::Redirects.load(path)
        end
      end
    end
  end

  def test_upload_preserves_keys_targets_and_metadata
    key = "quotes' spaces\tand\nnewlines.html"
    target = "/target?name=it's quoted&value=\"hello\"&literal=$(false);*&q=räv"
    client = Aws::S3::Client.new(stub_responses: true, region: "us-east-1")
    etag = %("#{Digest::MD5.hexdigest(target)}")
    client.stub_responses(:put_object, etag:)

    with_redirects(JSON.generate(key => target)) do |path|
      assert_equal({ key => target }, SitePreview::Redirects.load(path))
    end
    assert_equal etag, SitePreview::Redirects.upload(client, "preview", key, target)

    params = client.api_requests.fetch(0)[:params]
    body = params[:body].respond_to?(:read) ? params[:body].read : params[:body]
    expected = {
      bucket: "preview", key:, body: target,
      website_redirect_location: target, content_type: "text/html;charset=utf-8"
    }

    assert_equal expected, params.slice(*expected.keys).merge(body:)
  end

  def test_redirect_body_changes_when_target_changes
    client = Aws::S3::Client.new(stub_responses: true, region: "us-east-1")
    targets = ["/first/", "/second/"]
    targets.each do |target|
      SitePreview::Redirects.upload(client, "preview", "old.html", target)
    end
    bodies = client.api_requests.map do |request|
      body = request[:params][:body]
      body.respond_to?(:read) ? body.read : body
    end

    assert_equal targets, bodies
    refute_equal Digest::MD5.hexdigest(bodies[0]), Digest::MD5.hexdigest(bodies[1])
  end

  def test_upload_failure_propagates
    client = Aws::S3::Client.new(stub_responses: true, region: "us-east-1")
    client.stub_responses(:put_object, "AccessDenied")

    assert_raises(Aws::S3::Errors::AccessDenied) do
      SitePreview::Redirects.upload(client, "preview", "old.html", "/target/")
    end
  end

  def test_parallel_uploads_are_bounded_and_complete
    started = Queue.new
    release = Queue.new
    lock = Mutex.new
    active = peak = 0
    completed = []
    runner = Thread.new do
      SitePreview.parallel_each((0...24).to_a) do |item|
        lock.synchronize do
          active += 1
          peak = [peak, active].max
        end
        started << item
        release.pop
        lock.synchronize do
          completed << item
          active -= 1
        end
      end
    end

    Timeout.timeout(3) { 8.times { started.pop } }

    assert_equal(8, lock.synchronize { active })
    24.times { release << true }

    assert runner.join(3), "Worker pool did not finish"
    runner.value

    assert_equal({ completed: (0...24).to_a, peak: 8, active: 0 },
                 { completed: completed.sort, peak:, active: })
  ensure
    24.times { release << true }
    runner&.join(3)
  end

  def test_parallel_failure_waits_for_running_workers
    started = Queue.new
    release_failure = Queue.new
    release_others = Queue.new
    failed = Queue.new
    error = nil
    worker_threads = []
    lock = Mutex.new
    runner = Thread.new do
      SitePreview.parallel_each((0...8).to_a) do |item|
        lock.synchronize { worker_threads << Thread.current }
        started << item
        if item.zero?
          release_failure.pop
          failed << true
          raise "Simulated upload failure"
        end
        release_others.pop
      end
    rescue StandardError => e
      error = e
    end

    Timeout.timeout(3) { 8.times { started.pop } }
    release_failure << true
    Timeout.timeout(3) { failed.pop }

    assert_nil runner.join(0.02), "Returned while uploads were still running"
    7.times { release_others << true }

    assert runner.join(3), "Worker pool did not join after failure"

    assert_equal({ error: RuntimeError, message: "Simulated upload failure", workers_alive: false },
                 { error: error.class, message: error&.message, workers_alive: worker_threads.any?(&:alive?) })
  ensure
    release_failure << true
    7.times { release_others << true }
    runner&.join(3)
  end
end
