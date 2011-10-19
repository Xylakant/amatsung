require "bundler/gem_tasks"
require 'rake/testtask'

Rake::TestTask.new(:test) do |test|
  test.libs << 'test'
  test.pattern = 'test/tests/**/*_test.rb'
  test.verbose = true
  test.ruby_opts = ['-rubygems', '-rtest_helper']
end

task :default => :test
