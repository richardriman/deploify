module Deploify
  MAJOR = 0
  MINOR = 2
  PATCH = 24
  BUILD = nil

  if BUILD.nil?
    VERSION = [MAJOR, MINOR, PATCH].compact.join('.')
  else
    VERSION = [MAJOR, MINOR, PATCH, BUILD].compact.join('.')
  end
end
