# frozen_string_literal: true

require "stringio"

# A stdin double: a StringIO that claims to be a terminal, for the guard's
# typed-name prompt. Plain StringIO answers tty? with false.
class TtyInput < StringIO
  def tty? = true
end
