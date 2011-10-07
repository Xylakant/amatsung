# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "amatsung/version"

Gem::Specification.new do |s|
  s.name        = "amatsung"
  s.version     = Amatsung::VERSION
  s.authors     = ["Felix Gilcher"]
  s.email       = ["felix.gilcher@asquera.de"]
  s.homepage    = ""
  s.summary     = %q{Manage Tsung Load Testing on Amazon EC2 Instances}
  s.description = %q{Manage Tsung Load Testing on Amazon EC2 Instances}

  s.rubyforge_project = "amatsung"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.add_runtime_dependency "trollop"
  s.add_development_dependency "riot"
end
