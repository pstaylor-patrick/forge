# frozen_string_literal: true

module ForgeCli
  # Pure wait-time computation for a 429 or an exhausted rate-limit window.
  # Forge allows 60 requests per minute.
  module RateLimit
    DEFAULT_WAIT = 60
    EPOCH_THRESHOLD = 1_000_000_000

    # headers: a Hash with lowercase string keys (missing keys are fine).
    # now: Integer epoch seconds or a Time.
    # Prefers retry-after (seconds); else x-ratelimit-reset, read as an epoch
    # timestamp when large and as a delta otherwise; else DEFAULT_WAIT.
    def self.wait_seconds(headers, now: Time.now)
      retry_after = integer(headers["retry-after"])
      return [retry_after, 0].max if retry_after

      reset = integer(headers["x-ratelimit-reset"])
      return DEFAULT_WAIT unless reset
      return [reset - now.to_i, 0].max if reset > EPOCH_THRESHOLD

      [reset, 0].max
    end

    def self.integer(value)
      text = value.to_s.strip
      text.match?(/\A\d+\z/) ? text.to_i : nil
    end
    private_class_method :integer
  end
end
