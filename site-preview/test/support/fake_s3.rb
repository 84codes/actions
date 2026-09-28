# frozen_string_literal: true

require "aws-sdk-s3"
require "digest"
require "stringio"

# Store bytes and replacement metadata as S3 PUT requests would. Small listing
# pages and injected failures exercise recovery without credentials or network.
class FakeS3
  attr_accessor :now, :delay
  attr_reader :objects, :puts, :deletes, :fail_puts, :fail_nth_puts,
              :put_attempts, :fail_deletes, :active, :peak

  def initialize(now)
    @now = now
    @objects = {}
    @puts = []
    @deletes = []
    @fail_puts = []
    @fail_nth_puts = {}
    @put_attempts = Hash.new(0)
    @fail_deletes = []
    @delay = 0
    @active = @peak = 0
    @mutex = Mutex.new
  end

  def put_object(**request)
    check_bucket(request.fetch(:bucket))
    key = request.fetch(:key)
    attempt = @mutex.synchronize do
      @active += 1
      @peak = [@peak, @active].max
      @put_attempts[key] += 1
    end
    begin
      sleep @delay if @delay.positive?
      raise "Simulated PUT failure: #{key}" if @fail_puts.include?(key) || @fail_nth_puts[key] == attempt

      body = request.fetch(:body)
      body = body.read if body.respond_to?(:read)
      etag = %("#{Digest::MD5.hexdigest(body)}")
      @mutex.synchronize do
        @objects[key] = request.merge(body:, etag:, last_modified: @now)
        @puts << key
      end
      Aws::S3::Types::PutObjectOutput.new(etag:)
    ensure
      @mutex.synchronize { @active -= 1 }
    end
  end

  def get_object(bucket:, key:)
    check_bucket(bucket)
    object = @objects[key]
    raise Aws::S3::Errors::NoSuchKey.new(nil, key) unless object

    Aws::S3::Types::GetObjectOutput.new(body: StringIO.new(object.fetch(:body)))
  end

  def list_objects_v2(bucket:)
    check_bucket(bucket)
    objects = @objects.sort.map do |key, object|
      Aws::S3::Types::Object.new(
        key:, etag: object.fetch(:etag), last_modified: object.fetch(:last_modified)
      )
    end
    objects.each_slice(2).map { |contents| Aws::S3::Types::ListObjectsV2Output.new(contents:) }
  end

  def delete_objects(bucket:, delete:)
    check_bucket(bucket)
    @deletes << delete
    errors = delete.fetch(:objects).filter_map do |object|
      key = object.fetch(:key)
      if @fail_deletes.include?(key)
        Aws::S3::Types::Error.new(key:, code: "AccessDenied")
      else
        @objects.delete(key)
        nil
      end
    end
    Aws::S3::Types::DeleteObjectsOutput.new(errors:)
  end

  private

  def check_bucket(bucket)
    raise ArgumentError, "Unexpected bucket: #{bucket}" unless bucket == "preview"
  end
end
