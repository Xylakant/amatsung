require "amatsung/version"
require "amatsung/config"
require "amatsung/node/node"
require "amatsung/testrun"

module Amatsung

  SUPPORTED_PROVIDERS = %w<AWS>

  class InvalidConfig < ArgumentError; end
end
