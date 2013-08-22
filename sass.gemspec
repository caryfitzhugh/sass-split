require 'rubygems'

# Note that Sass's gem-compilation process requires access to the filesystem.
# This means that it cannot be automatically run by e.g. GitHub's gem system.
# However, a build server automatically packages the master branch
# every time it's pushed to; this is made available as a prerelease gem.
SASS_GEMSPEC = Gem::Specification.new do |spec|
  spec.rubyforge_project = 'sass-split'
  spec.name = 'sass-split'
  spec.summary = "A powerful but elegant sass splitter gem"
  spec.version = File.read(File.dirname(__FILE__) + '/VERSION').strip
  spec.authors = ['Cary Fitzhugh/Ziplist', 'Nathan Weizenbaum', 'Chris Eppstein', 'Hampton Catlin']
  spec.description = <<-END
      This is really sass-split.  Just processes sass, splits it into dynamic and static files.
    END

  spec.required_ruby_version = '>= 1.8.7'
  spec.add_development_dependency 'yard', '>= 0.5.3'
  spec.add_development_dependency 'maruku', '>= 0.5.9'

  readmes = Dir['*'].reject{ |x| x =~ /(^|[^.a-z])[a-z]+/ || x == "TODO" }
  spec.executables = ['sass-split']
  spec.files = Dir['rails/init.rb', 'lib/**/*', 'vendor/**/*',
    'bin/*', 'test/**/*', 'extra/**/*', 'Rakefile', 'init.rb',
    '.yardopts'] + readmes
  spec.has_rdoc = false
  spec.test_files = Dir['test/**/*_test.rb']
  spec.license = "MIT"
end
