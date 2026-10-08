# frozen_string_literal: true

module ForgeCli
  # Base error. bin/forge maps each subclass to an exit code:
  # AuthError 2, NotFoundError 3, ApiError 4, PartialFailure 5, anything else 1.
  class Error < StandardError
    attr_reader :status, :body

    def initialize(msg = nil, status: nil, body: nil)
      super(msg)
      @status = status
      @body = body
    end
  end

  class AuthError < Error; end
  class NotFoundError < Error; end
  class ApiError < Error; end
  class RateLimitError < ApiError; end
  class AmbiguousError < Error; end
  class GuardRefused < Error; end   # destructive command, stdin not a TTY, no --yes
  class Aborted < Error; end        # typed confirmation did not match
  class DeployFailed < Error; end   # deploy --wait ended in a failed status or timed out
  class PartialFailure < Error; end # reserved (exit 5)
end
