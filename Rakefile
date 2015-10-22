require 'rbconfig'
require 'shellwords'

class RubyCommand
  attr_accessor :env_vars, :ruby_path, :ruby_flags, :executable

  def initialize(env_vars:{}, ruby_path:RbConfig.ruby, ruby_flags:[], executable_args:[])
    self.env_vars         = env_vars
    self.ruby_path        = ruby_path
    self.ruby_flags       = ruby_flags
    self.executable_args  = executable_args
    yield self if block_given?
  end

  attr_reader :executable_args
  def executable_args=(args)
    @executable_args = split_args args
  end

  def set_executable(code:nil, program_name:nil, filepath:nil)
    if 1 != [code, program_name, filepath].compact.length
      raise ArgumentError, "You must have exactly 1 executable!"
    end
    self.executable = [filepath]           if filepath
    self.executable = ['-S', program_name] if program_name
    self.executable = ['-e', code, '--']   if code
    self
  end

  def sh_args
    [ env_vars,
      ruby_path,
      split_args(ruby_flags),
      (executable || raise("No executable!")),
      executable_args,
    ].flatten
  end

  def split_args(args)
    return args unless args.respond_to? :shellsplit
    args.shellsplit
  end
end


class TestCommand
  attr_accessor :ruby_command

  def initialize(args)
    args[:ruby_path]  ||= FileUtils::RUBY
    args[:ruby_flags] ||= Hoe::RUBY_FLAGS
    self.ruby_command = RubyCommand.new(args)
  end

  def build
    ruby_command.sh_args
  end
end


class MinitestTestCommand < TestCommand
  FILTER = (ENV["FILTER"] || ENV["TESTOPTS"] || "").dup
  FILTER << " -n #{ENV["N"]}" if ENV["N"]

  attr_accessor :autorun_files, :test_prelude, :test_globs

  def initialize(executable_args: FILTER, **args)
    super executable_args: executable_args, **args
    self.verbose       = false
    self.autorun_files = ['minitest/autorun']
    self.test_globs    = [ "test/**/{test,spec}_*.rb",
                           "test/**/*_{test,spec}.rb"]
  end

  def build_all
    ruby_command.set_executable code: code_for(test_files)
    build
  end

  def build_each
    test_files.each do |test_file|
      ruby_command.set_executable code: code_for(test_file)
      yield build
    end
  end

  attr_reader :verbose
  def verbose=(verbose)
    @verbose = verbose
    args = ruby_command.executable_args
    args.delete '-v'
    args.unshift '-v' if verbose
  end

  def define_tasks(rake_app)
    rake_app.desc "Run the test suite. Use FILTER or TESTOPTS to add flags/args."
    rake_app.task(:test) { rake_app.sh *build_all }

    rake_app.desc "Print out the test command. Good for profiling and other tools."
    rake_app.task(:test_cmd) { rake_app.sh *build_all }

    rake_app.desc "Show which test files fail when run alone."
    rake_app.task :test_deps do
      build_each do |command|
        # not going to try to figure out how to do this
        # null_dev = Hoe::WINDOZE ? "> NUL 2>&1" : "> /dev/null 2>&1"
        # command.silence_stdout
        rake_app.sh *command do |ok, status|
          $stdout.puts "Dependency Issues: #{test}"
        end
      end
    end

    rake_app.desc "Show bottom 25 tests wrt time."
    rake_app.task "test:slow" do
      # and what to do for this one? seems like this idea would have to become its own lib
      # ie now we need a generic shell invocation object, and a pipeline we can put them into
      verbose = true
      rake_app.sh "rake TESTOPTS=-v | sort -n -k2 -t= | tail -25"
    end

    rake_app.desc "Run the default task(s)."
    rake_app.task :default => :test
  end

  private

  def test_files
    test_globs.sort.map { |g| Dir.glob g }
  end

  def code_for(test_files)
    [ *require_statements_for("rubygems"),
      *Array(test_prelude),
      *require_statements_for(autorun_files, test_files),
    ].join("; ")
  end

  def require_statements_for(*filenames)
    filenames.flatten.compact.map { |filename| "require #{filename.to_s.inspect}" }
  end
end


class MultirubyCommand < TestCommand
  attr_accessor :skip

  def initialize(executable_args: ['-S', 'rake'], **args)
    self.skip = []
    super(executable_args: executable_args, **args)
      .set_executable program_name: 'multiruby'
  end

  def build
    ruby_command.env_vars["EXCLUDED_VERSIONS"] = skip.join(":")
    super
  end

  def define_tasks(rake_app)
    rake_app.desc "Run the test suite using multiruby."
    rake_app.task(:multi) { sh *build }
  end
end


module RakeAppDsl
  include FileUtils

  # have to use last_description b/c desc always talks to the singleton application
  # https://github.com/ruby/rake/blob/11be647a793ad06753a38cd4e1bfdac2ebd3c917/lib/rake/dsl_definition.rb#L172
  def desc(description)
    self.last_description = description
  end

  def task(*args, &block)
    define_task(Rake::Task, *args, &block)
  end
end

class Hoe
  default_ruby_flags = "-I#{%w[lib bin test .].join(File::PATH_SEPARATOR)}"
  RUBY_FLAGS = ENV["RUBY_FLAGS"] || default_ruby_flags

  def self.spec(name, rake_app, &block)
    # faking the plugin system for this thought experiment
    hoe = new name, rake_app
    hoe.extend Hoe::Test
    hoe.initialize_test
    hoe.instance_eval(&block)
    hoe.define_test_tasks
    hoe
  end

  attr_accessor :name, :test_task, :rake_app
  def initialize(name, rake_app)
    self.name     = name
    self.rake_app = rake_app.extend(RakeAppDsl)
  end
end


module Hoe::Test
  attr_accessor :test_command, :multiruby_command

  def initialize_test
    self.test_command      = MinitestTestCommand.new
    self.multiruby_command = MultirubyCommand.new
  end

  def define_test_tasks
    test_command      && test_command.define_tasks(rake_app)
    multiruby_command && multiruby_command.define_tasks(rake_app)
  end
end


class MrspecCommand < TestCommand
  TESTOPTS = (ENV["TESTOPTS"] || "").dup

  def initialize(executable_args: TESTOPTS, **args)
    super(executable_args: executable_args, **args)
      .set_executable(program_name: 'mrspec')
  end

  def define_tasks(rake_app)
    rake_app.desc "Run the test suite. Use TESTOPTS to add flags/args."
    rake_app.task(:test) { rake_app.sh *build }
  end
end


Hoe.spec 'myproj', Rake.application do
  if rand(2) == 1
    test_command.test_prelude = "require 'minitest/pride'"
  else
    self.test_command = MrspecCommand.new
  end
end


# # so I don't have to keep typing `ruby -I ../../lib -S rake`
# local_hoe = File.expand_path '../..', __dir__
# if File.basename(local_hoe) == 'hoe'
#   $LOAD_PATH.unshift File.join(local_hoe, 'lib')
# end

# require "rubygems"
# require "hoe"

# Hoe.spec "myproj" do
#   Hoe::RUBY_FLAGS.gsub! '-w ', ''
#   self.testlib      = :none
#   mrspec_path       = Gem::Specification.find_by_name('mrspec').bin_file('mrspec')
#   self.test_prelude = "load #{mrspec_path.inspect}"
#   # path = "minitest/pride"
#   # spec = Gem::Specification.find_by_path(path)
#   # spec.activate # doesn't seem to be a way to find the path without activating the gem
#   # fullpath = spec.to_fullpath(path)
#   # task(:test) { self.test_globs << fullpath }

#   developer("Josh Cheek", "josh.cheek@gmail.com")
#   license "MIT"
# end
