First part is an overview of thoughts, musings, suggestions, contemplations.
Culminates in a reasonably sized code experiment (in the [Rakefile](https://github.com/JoshCheek/playing-with-hoe/blob/master/Rakefile)),
which shed some insight, but didn't specifically compel me to any certainty.

Second part is a "document my attempt to use this", which has some value in that it shows with some amount of accuracy,
how I attempt to make sense of a library. It's probably also good in that most of us don't get to see people attempt
to use the things we make, so we're probably expecting something different than the reality. And lastly, it might
have value in that it shows a certain set of procedures (namely how I use pry) that have worked well for me.


## Part 1: attempting to gather my thoughts

* It would be super helpful to declare certain things loud and up front, b/c for someone coming in, who doesn't know how they work, it's really unclear where to start. In particular: `rake newb`. Maybe an explicit check for something like whether the gems have been isolated, and then emit a notice like "if this is your first time in the project, run `rake newb`" eg the way it warns about things like missing files.
* Within the lib, making it clear that `Hoe.spec` is the entry point (I know it seems super obvious now, but I thought it was defining the gemspec, so i assumed `require "hoe"` must have some side-effect in there somewhere) There are a number of ways: you could just put that front-center in the readme, though I generally feel like documentation is for when you can't find a good way to make something obvious. You could rename it to something like `Hoe.define` or `Hoe.create` or `Hoe.configure`, though I dislike that one as it implies a singleton configuration object, which isn't accurate. Actually, my confusion was reasonable since `Hoe#spec` returns a Gem::Specification. If you dislike changing the name, then allowing me to see the wiring would have really helped me figure it out: `Hoe.spec('myproject', Rake.application) { ... }` this one change would immediately allow me to see it's the entry point, give me context into what Hoe does / how it works, and make me trust the lib more because it implies it's not going to go mess with the world in ways that I don't know about / expect (eg the same way I experience a sense of trust when I see a binary explicitly passing ARGV/$stdout/$stdin to the runner).
* `test_globs` is defined on `Hoe`, but seems like it should be defined on `Hoe::Test` (which would ultimately make its way back into `Hoe`, when the plugin gets extended onto the instance) https://github.com/seattlerb/hoe/blob/215e47bb1e201ea1bef28f919393babc764e05a5/lib/hoe.rb#L244 and https://github.com/seattlerb/hoe/blob/215e47bb1e201ea1bef28f919393babc764e05a5/lib/hoe.rb#L641-L642
* `Hoe::plugin :thingy` in the readme is confusing, I was skimming the readme and had to stop for about 5 seconds before my brain made sense of the syntax.
* Given that the plugin uses isolate (which, I know very little about), it seems like it should not need to load rubygems. This could lead to a dramatic speedup. I played around with it a bit, and, without making any changes to any existing code, got 50% to 200% speedup running hoe's test suite with `time rake test` and `time ./isolated_rake test`, where isolated_rake was defined as:

  ```ruby
  #!/usr/bin/env ruby --disable-gems
  require 'rbconfig'
  isolated_path = File.expand_path "tmp/isolate/#{RUBY_ENGINE}-#{RbConfig::CONFIG['ruby_version']}", __dir__
  ENV['GEM_HOME'] = ENV['GEM_PATH'] = isolated_path.freeze
  load File.join(isolated_path, 'bin', 'rake')
  ```
* (NOTE: this assessment is inaccurate, but I'll leave it as it illustrates how a new user probably makes sense of things) There is no good way to add options that don't affect all invocations of Ruby. [This](https://github.com/seattlerb/hoe/blob/215e47bb1e201ea1bef28f919393babc764e05a5/lib/hoe/test.rb#L159) is how the invocation is built up: `"#{Hoe::RUBY_FLAGS} -e '#{tests.join("; ")}' -- #{FILTER}"` which means that if you wanted to require a file, you have a limited number of possibilities, all with issues:
  * Add it to `Hoe::RUBY_FLAGS`, which affects other invocations of Ruby. eg in `rake test irb`, the `irb` task would inherit these options
  * Add it to `Hoe#test_globs`, which won't work unless you pass the full path (eg `path = "minitest/pride"; spec = Gem::Specification.find_by_path(path); spec.activate; self.test_globs << spec.to_fullpath(path)`), but even then, this only works for require statements, and not other flags.
  * Add it to `Hoe::Test::FILTER`, but this can only support what minitest's option parser handles, eg adding `Hoe::Test::FILTER << '-r minitest/pride'` to the Rakefile leads to /Users/josh/.rubies/ruby-2.2.2/bin/ruby -w -Ilib:bin:test:. -e 'require "rubygems"; require "minitest/autorun"; require "test/test_myproj.rb"' -- -r minitest/pride` which raises `invalid option: -r`
  * Add it to `ENV['RUBYOPT']`, eg `ENV["RUBYOPT"] = ENV.fetch("RUBYOPT", "") + " -r minitest/pride"`, but this suffers the same issue as `Hoe::RUBY_FLAGS`, where it affects all invocations of Ruby, not just the test.
* I just realized that the above criticism is wrong, you can write Ruby in `test_prelude`, as long as you don't use single quotes. Or possibly close off the opening single quote, shell escape some large amount of Ruby,and then reopen it: `ruby = "require 'minitest/pride'"; self.test_prelude = "'#{ruby.shellescape}'"`
* Probably the variable `tests` should be named something different, https://github.com/seattlerb/hoe/blob/215e47bb1e201ea1bef28f919393babc764e05a5/lib/hoe/test.rb#L151 I think that name made it difficult to think about what the pieces were. Maybe something like this:

  ```ruby
  def make_test_cmd
    unless SUPPORTED_TEST_FRAMEWORKS.key?(testlib)
      raise "unsupported test framework #{testlib}"
    end

    framework_files = SUPPORTED_TEST_FRAMEWORKS[testlib]
    test_files      = test_globs.sort.map { |g| Dir.glob g }

    code = [
      *require_statements_for("rubygems"),
      *Array(test_prelude),
      *require_statements_for(framework_files, test_files),
    ].join("; ")

    "#{Hoe::RUBY_FLAGS} -e '#{code}' -- #{FILTER}"
  end

  def require_statements_for(*filenames)
    filenames.flatten.compact.map { |filename| "require #{filename.to_s.inspect}" }
  end
  private :require_statements_for
  ```

  Note that you can pass an array of arguments to both Ruby and sh (nice thing about passing them to sh is that it lets you set environment variables). The nice thing about this is that everyone doesn't have to consider escaping at each level. Something like this:

  ```ruby
  ruby *[Hoe::RUBY_FLAGS.shellsplit, '-e', code, '--', FILTER.shellsplit].flatten
  ```
* I was thinking about how to hook up mrspec. I got it with:

  ```ruby
  Hoe::RUBY_FLAGS.gsub! '-w ', ''
  self.testlib      = :none
  mrspec_path       = Gem::Specification.find_by_name('mrspec').bin_file('mrspec')
  self.test_prelude = "load #{mrspec_path.inspect}"
  ```

  It's just that I know I could just do this, which runs it just fine (`rake test2 TESTOPTS='-f p'`), is easier to see, and gives me more fine-grained control over the invocation. eg I can remove warnings for just this one invocation instead of all invocations.

  ```ruby
  task :test2 do
    ruby_flags = Hoe::RUBY_FLAGS.gsub '-w ', ''
    ruby "#{ruby_flags} -S mrspec #{Hoe::Test::FILTER}"
  end
  ```
* Been thinking about it and trying to identify why it's hard. Got 2 or 3 potential reasons, and some code exploring the second one.

  The first is that Rake might be the wrong tool for this level of configuration. It's fine for something as simple as "run that command that I always run", but we're trying to turn it into a generic test runner, and that's not where its strengths are. I primarily think of it as a way to specify dependencies, and think that its convenience was high enough that it got turned into a generic script runner (note that I'm utterly ignorant of the history of make, so its possible that this history preceded it, and its even possible that it works well and I'm wrong). As an example, it seems to be missing the concept of "this is the code that fulfills this task", when I wanted to run Rails tests with `mrspec`, I had to do this crazy hacking into Rake to get the old task to disable it. I thought "What does RSpec do? Surely they're hitting the same thing" so I went and checked it out, and yes, they did hit it, and they used the same hack I'd come up with: https://github.com/rspec/rspec-rails/blob/c3ac2315066d8c6d09028499737d0b50227168ed/lib/rspec/rails/tasks/rspec.rake#L2-L4 In the same way that you want to conveniently specify the -n flag for minitest, I want to specify `--fail-fast` and `--tag tagname` so incredibly frequently, that I'd want a similar capacity to toggle them dynamically. This implies a general need to dynamically interact with the test tools, but we're relegated to environment variables, and it's questionable about whether the interfaces are generic enough to specify in an agnostic manner.

  The second is that this level of configuration might just require more modularity. It seems to be trying to configure all test runners with a single set of variables. To do that, we either give up the ability to talk about each tool with nuance, or we push the variables into different namespaces so that the different runners can take full advantage of their knowledge about the environment. I think that of these options, allowing each tool to take advantage of its abilities is more appealing. You can still get a generic set of capability by defining an interface that any test plugin must support (eg .all_files, .run_one_test, .run_one_file)

  The third possibility is that if the lower level building blocks were more expressive, then we would be able to handle the spectrum of invocations more effectively. Maybe there needs to be an `ExecutableTask` the way there is a `FileTask`. I started trying to think about what it would look like to use rake for this kind of thing, my first thought was that you'd add a dependency to modify it the way you want, eg `task test: 'test:record_slowest'` where `test:record_slowest` would do something to modify an invocation that is being built up. This seemed interesting, so I decided to try it. In the end, I never made it behave that way, because it means that they need to be executing in some shared context where they are building up the invocation. As I pushed my experiment in that direction, it mostly wound up behaving more like what I described in the second paragraph, where there is a `MinitestTestCommand` object (things moved more and I'm now thinking it should maybe be `MinitestTasks`, but I'll leave it, it was just an experiment). At first I really liked the `RubyCommand` object, but it wasn't able to handle the pipeline: https://github.com/seattlerb/hoe/blob/215e47bb1e201ea1bef28f919393babc764e05a5/lib/hoe/test.rb#L114 or redirects https://github.com/seattlerb/hoe/blob/215e47bb1e201ea1bef28f919393babc764e05a5/lib/hoe/test.rb#L102 kind of made me think there should just be a generic lib built up around this (also, as I think about it, there likely is). Anyway, the experiment is sitting in the [Rakefile](https://github.com/JoshCheek/playing-with-hoe/blob/master/Rakefile).



## Part 2: Documenting my attempt to use the lib

----- 1. setting up the gem locally -----

Cloning the repo so I can look at it locally.

Having difficulty figuring out where to start, usually I start with `bundle` to install gems, and then figure out how to run the tests (usually `rake` or `rspec` or an executable file). Don't see any of these, was going to check out the gemspec to get a toplevel feel for it, but can't find it. Seem to remember your projects use `isolate` instead of bundler, but I've only ever looked into that once (prob should have written down what I figured out). Also remember that one of these tools generates the gemspec from a more abstract definition, probably from the Rakefile, don't see it in there (update: realized it's `Hoe.spec`). Quick skim of the readme (note: took about 5 seconds to realize `Hoe::plugin :thingy` was a method call) and then check the tasks `rake -T`, looks like the second column is a namespace, so `rake -T deps`, sort of expecting a `deps:install` task. Trying `rake -T install`, I see `rake install_plugins` Ran it and killed it b/c it took about a minute w/o giving feedback. Here's the stacktrace:

```
rake install_plugins
^Crake aborted!
Interrupt:
/Users/josh/deleteme/hoe/lib/hoe/package.rb:104:in `system'
/Users/josh/deleteme/hoe/lib/hoe/package.rb:104:in `install_gem'
/Users/josh/deleteme/hoe/lib/hoe/deps.rb:207:in `block in install_missing_plugins'
/Users/josh/deleteme/hoe/lib/hoe/deps.rb:199:in `each'
/Users/josh/deleteme/hoe/lib/hoe/deps.rb:199:in `install_missing_plugins'
/Users/josh/deleteme/hoe/lib/hoe/deps.rb:48:in `block in define_deps_tasks'
Tasks: TOP => install_plugins
(See full trace by running task with --trace)
```

Running it again, it completed quickly (idk if something went wrong the first time, or if it completed some significant portion of the work, and then resumed where it left off).

`rake -T test` reveals `rake test_cmd` which is nice (it's the thing I had been looking for in that issue on stripe's ruby client). Seems like it should be `rake test:cmd`, though.

Running `rake test`, it installed gems via isolate. Looking around, they're in tmp/isolate, which is pretty nice, I went to a lot of work to get bundler to do this a couple of different times. It still takes ~1s to run the tests, though, I probably need to explicitly disable rubygems (I'm assuming this is the point of isolate) so try `ruby --disable-gems -S rake test` but it's not quicker. About to run the test command by hand but I see `-e 'require "rubygems";` so that's probably why it takes so long (looks like I have 414 installed `gem list | tr , \n | wc -l`)

Anyway, tests pass, so do `rake test:slow` Figure I'll try generating a project and seeing how to use the test task to get a feel for it.


----- 2. Setting up a hoe project -----

Looks like the binary is `sow`. Output of `sow -h` implies I give it a style, but not sure what options are available. Maybe it's b/c I'm sitting in hoe's dir as I try this, make tmp/myproj and try from there. Same output. Looking at the bin, it's apparently any dir in ~/.hoe_template, which only contains default, so I'll omit this option. Guessing it's going to generate a dir, yep. Rerun it from tmp dir `cd ..; rm -r myproj; ../bin/soe myproj; cd myproj`

A bunch of erb outputs, guessing these are the templates. Mildly curious if there's some way to pass environment variables or something, to fill in the values I'm supposed to go fix. Contemplate it for a moment, then decide I'm not that curious.

Ahh, actually, the comment says "# HEY! If you fill these out in ~/.hoe_template/default/Rakefile.erb then", so I guess it wasn't an unreasonable thing to wonder about :P

Decide to use git so I can better document what I try... not sure if it's a problem to init a git repo within another repo... guess we'll find out! Looks like it works.

Updating the Rakefile and README.txt, guessing the format is rdoc, which I'm realizing I don't know, also curious that it doesn't end in .rdoc (maybe it is just plain text, but it seems structured).

Oh, apparently I'm supposed to run `rake newb`, go back to `hoe` and run that. Everything works and looks good, wish I'd realized that a while ago (it's in a section titled DEVELOPERS, which is in the generated README, but not in Hoe's).

Glance through the rest of the files, delete History and bin, surprised to see `require "myproj"` in test, realizing the test task must add the lib dir to the `$LOAD_PATH`

Maybe I fucked something up, `rake -T` says "**  is missing or in the wrong format for auto-intuiting. run `sow blah` and look at its text files". Grep the output, but don't see any tasks listed with double asterisks.

```
rake -T 2>&1 | grep '\*\*'
**  is missing or in the wrong format for auto-intuiting.
```

Maybe I messed it up in the Manifest? Trying `sow blah` b/c it says to. It generates a project `blah`, not sure if I'm supposed to compare that project to my current one to figure out what I fucked up, or if "blah" was a placeholder for "whatever the correct command happens to be". Check out parent commit to see if it's the Readme or the deleted files. It's apparently the deleted files. Check the manifest, I removed them both. `ag hist`only shows a commented out plugin in the Rakefile, and every gem definitely doesn't have a bin. Check the source, `warn "** #{name} is missing or in the wrong format for auto-intuiting."` (fwiw, I've started placing `.inspect` on interpolations like this)

```ruby
From: /Users/josh/deleteme/hoe/lib/hoe.rb @ line 750 Hoe#missing:

    748: def missing name
    749:   require "pry"
 => 750:   binding.pry
    751:   warn "** #{name} is missing or in the wrong format for auto-intuiting."
    752:   warn "   run `sow blah` and look at its text files"
    753: end
```

Apparently it's the history file.

```ruby
[3] pry(#<Hoe>)> require 'binding_of_caller'
[4] pry(#<Hoe>)> binding.of_caller(16).pry # I have that offset memorized o.O

From: /Users/josh/deleteme/hoe/lib/hoe.rb @ line 683 Hoe#intuit_values:

    660: def intuit_values
    # ...
    679:   self.changes ||= begin
    680:                      h = File.read_utf(history_file)
    681:                      h.split(/^(={2,}|\#{2,})/)[1..2].join.strip
    682:                    rescue
 => 683:                      missing history_file
    684:                      ""
    685:                    end
    686: end

[1] pry(#<Hoe>)> history_file
=> nil
[2] pry(#<Hoe>)> show-source history_file

From: /Users/josh/deleteme/hoe/lib/hoe.rb @ line 183:
Owner: Hoe
Visibility: public
Number of lines: 1

attr_accessor :history_file
```

Not sure what it's for, but I'll put it back.


----- 3. Run a test using the test task -----

Okay, lets make a test, update test/test_myproj.rb to look like this:

```ruby
gem "minitest"
require "minitest/autorun"
require "myproj"

class TestMyproj < Minitest::Test
  def test_version_matches_my_expectation
    assert_equal '1.0.0', Myproj::VERSION
  end
end
```

Trying to remember if I ate today, contemplating drinking, not because I want to drink, but because I desire something flavourful.

So there's no test task in the Rakefile, and `Hoe.plugin :minitest` is commented out still, but I have `test` and `test:slow` tasks available. Not really sure why. Maybe `minitest` plugin is different from the one in lib? Then again `Hoe.plugin :history` is commented out, but it still got upset about the history file, so maybe this is a list of pre-installed plugins? `cat ~/.hoe_template/default/Rakefile.erb` Doesn't look like it, based on `extra = found - Hoe.plugins - [:rake]` Lets see what's in there

```
$ ruby -r hoe -e 'p Hoe.plugins'
[:clean, :debug, :deps, :flay, :flog, :newb, :package, :publish, :gemcutter, :signing, :test]
```

Yeah, looks like `:test` is not the same as `:minitest`. Still not sure why it disliked the history_file, the readme said something about the default plugins being extracted, maybe this functionality wasn't completely extracted, or maybe it extends some default amount of functionality.

Anyway, lets see what this task does:

```
$ rake test
/Users/josh/.rubies/ruby-2.2.2/bin/ruby -w -Ilib:bin:test:. -e 'require "rubygems"; require "minitest/autorun"; require "test/test_myproj.rb"' --
Run options: --seed 47591

# Running:

.

Finished in 0.001216s, 822.6214 runs/s, 822.6214 assertions/s.

1 runs, 1 assertions, 0 failures, 0 errors, 0 skips
```

Looks good, not sure why bin or root are in the load path. I'm imagining trying to explain to students why `require "lib/whatever"` is wrong even though it works. They have such a really hard time with paths, I've started advocating `require_relative` to them, b/c they can actually reason about it, and really, it's not that bad (made it pretty easy to understand when I played w/ npm).

Lets try adding minitest/pride. Looking at the Rakefile, don't see anything obvious, maybe I need to do something similar to `Hoe.spec`, maybe something like `Hoe.test_task`, I'm remembering the plugins were modules, maybe they get extended onto `main`, or maybe included into `Hoe`. Lets find out:

```ruby
rake -T

From: /Users/josh/deleteme/hoe/tmp/myproj/Rakefile @ line 25 :

    20:
    21:   license "MIT"
    22: end
    23:
    24: require "pry"
 => 25: binding.pry

# not an ancestor of main
[1] pry(main)> singleton_class.ancestors
=> [#<Class:#<Object:0x007fb2318e1c88>>, Rake::DSL, Rake::FileUtilsExt, FileUtils, FileUtils::StreamUtils_, Object, PP::ObjectMixin, Kernel, BasicObject]

# no methods about testing in here (which is strange, given Kernel#test, looks like it doesn't show private methods by default)
[2] pry(main)> ls --grep test

# Hoe is a class
[3] pry(main)> Hoe.class
=> Class

# so we're probably interested in an instance of it... lots of methods, that's probably a yes
[4] pry(main)> Hoe.instance_methods - Class.new.instance_methods
=> [:author,
 :author=,
...

# lets just rule class methods out real quick
[5] pry(main)> Hoe.methods - Class.new.methods
=> [:add_include_dirs, :bad_plugins, :load_plugins, :normalize_names, :plugin, :plugins, :spec]

# Okay, lets go check Hoe out
[6] pry(main)> cd Hoe
[7] pry(Hoe):1> ls --grep test
Hoe#methods: test_globs  test_globs=
instance variables: @bad_plugins  @files  @found  @loaded
class variables: @@plugins

# hmm, take a guess at what the module name was
[9] pry(Hoe):1> Hoe::Test
=> Hoe::Test

# What do you provide?
[10] pry(Hoe):1> ls -M Hoe::Test
Hoe::Test#methods:
  define_test_tasks  make_test_cmd   multiruby_skip=  rspec_dirs=    rspec_options=  test_prelude=  testlib=            try_loading_rspec2
  initialize_test    multiruby_skip  rspec_dirs       rspec_options  test_prelude    testlib        try_loading_rspec1

# Okay, plugin system said `define_..._tasks` was the entry point, what's it do?
[11] pry(Hoe):1> show-source Hoe::Test#define_test_tasks

# Okay, that method you pointed me at is in the rake task, somehow I have to give it the options it needs
# How is this all wired in? Is it extended onto itself?
[12] pry(Hoe):1> Hoe::Test.ancestors.include? Hoe::Test
=> true

# Included into Hoe?
[13] pry(Hoe):1> Hoe.ancestors.include? Hoe::Test
=> false

# Wait, is that a legit test? Let me try on an instance
[15] pry(Hoe):1> Hoe.allocate.singleton_class.ancestors.include? Hoe::Test
=> false

# I'm in Hoe, does it have a singleton instance or something?
[16] pry(Hoe):1> ls -i
instance variables: @bad_plugins  @files  @found  @loaded
class variables: @@plugins

# hmm, back to main to see what got required / used
[17] pry(Hoe):1> exit
=> Hoe
[18] pry(main)> whereami 100

# ...omitted...
```

Not sure how to get the hoe instance to tell it the args. Going to get into the context where it gets defined.

```ruby
rake -T

From: /Users/josh/deleteme/hoe/lib/hoe/test.rb @ line 77 Hoe::Test#define_test_tasks:

    72:   ##
    73:   # Define tasks for plugin.
    74:
    75:   def define_test_tasks
    76:     require "pry"
 => 77:     binding.pry
    78:     default_tasks = []
    79:
    80:     task :test
    81:
    82:     if File.directory? "test" then

[1] pry(#<Hoe>)> caller.grep(/\/hoe\//)
=> ["/Users/josh/deleteme/hoe/lib/hoe/test.rb:77:in `define_test_tasks'",
 "/Users/josh/deleteme/hoe/lib/hoe.rb:730:in `block in load_plugin_tasks'",
 "/Users/josh/deleteme/hoe/lib/hoe.rb:724:in `each'",
 "/Users/josh/deleteme/hoe/lib/hoe.rb:724:in `load_plugin_tasks'",
 "/Users/josh/deleteme/hoe/lib/hoe.rb:808:in `post_initialize'",
 "/Users/josh/deleteme/hoe/lib/hoe.rb:390:in `spec'",
 "/Users/josh/deleteme/hoe/tmp/myproj/Rakefile:18:in `<top (required)>'"]
```

Okay, it hit `define_test_tasks` before the pry in the Rakefile, and line 18 of the Rakefile calls `Hoe.spec`. Checking the readme again, it says "Plugins can also define their own methods and they'll be available as instance methods to your hoe-spec" which I didn't really process. I probably assumed it was something to do with the gemspec and just moved on. Now I'm guessing it's `self` inside the block.

I'm realizing that the approach I take to figuring this out is not the approach I would actually take. In actuality, I'd be jumping around way more, eg I'd just pry into `Hoe.spec` to see. But b/c I'm trying to document the thought process, I went to read the source code first, and found https://github.com/seattlerb/hoe/blob/215e47bb1e201ea1bef28f919393babc764e05a5/lib/hoe.rb#L217 but I'm kind of expecting there to be a `Hoe.spec` and a `Hoe#spec`, which are simply not the same thing, and as I think about why, I can identify the reasons, but in reality, I wouldn't be thinking about why, yet, and I'd not have noticed this yet. Makes me wonder if my entire exploration is a pretense. Maybe I should record these things? Even then I wind up trying to explain what I'm thinking, which alters my epistemology, which alters my analysis. I'm going to continue, though, b/c I'm already this far *shrug*

Anyway, there's the line that explains how it fits together: https://github.com/seattlerb/hoe/blob/215e47bb1e201ea1bef28f919393babc764e05a5/lib/hoe.rb#L389, so the `spec` is the instance of `Hoe`, and is probably called that b/c it specifies how to configure Hoe, and doesn't inherently have anything to do with the gemspec, other than that's one its attributes.

Okay, lets figure out how to get it to require minitest/pride:

```
$ rake -T

From: /Users/josh/deleteme/hoe/tmp/myproj/Rakefile @ line 23 :

    18: Hoe.spec "myproj" do
    19:   developer("Josh Cheek", "josh.cheek@gmail.com")
    20:
    21:   license "MIT"
    22:   require "pry"
 => 23:   binding.pry
    24: end

# what testy things are here?
[1] pry(#<Hoe>)> ls --grep test
Hoe#methods: test_globs  test_globs=
Hoe::Test#methods: define_test_tasks  initialize_test  make_test_cmd  test_prelude  test_prelude=  testlib  testlib=
Hoe::Deps#methods: get_latest_gems

# what do these promising things return?
[2] pry(#<Hoe>)> testlib
=> :minitest
[3] pry(#<Hoe>)> make_test_cmd
=> "-w -Ilib:bin:test:. -e 'require \"rubygems\"; require \"minitest/autorun\"; require \"test/test_myproj.rb\"' -- "


# what should I look at next?
[4] pry(#<Hoe>)> show-source make_test_cmd

From: /Users/josh/deleteme/hoe/lib/hoe/test.rb @ line 144:
Owner: Hoe::Test
Visibility: public
Number of lines: 17

def make_test_cmd
  unless SUPPORTED_TEST_FRAMEWORKS.key?(testlib)
    raise "unsupported test framework #{testlib}"
  end

  framework = SUPPORTED_TEST_FRAMEWORKS[testlib]

  tests = ["rubygems"]
  tests << framework if framework
  tests << test_globs.sort.map { |g| Dir.glob(g) }
  tests.flatten!
  tests.map! { |f| %(require "#{f}") }

  tests.insert 1, test_prelude if test_prelude

  "#{Hoe::RUBY_FLAGS} -e '#{tests.join("; ")}' -- #{FILTER}"
end


# curiosity
[5] pry(#<Hoe>)> Hoe::Test::SUPPORTED_TEST_FRAMEWORKS
=> {:testunit=>"test/unit", :minitest=>"minitest/autorun", :none=>nil}
[6] pry(#<Hoe>)> test_globs
=> ["test/**/{test,spec}_*.rb", "test/**/*_{test,spec}.rb"]
[7] pry(#<Hoe>)> test_prelude
=> nil
[8] pry(#<Hoe>)> show-source test_prelude

From: /Users/josh/deleteme/hoe/lib/hoe/test.rb @ line 49:
#...
attr_accessor :test_prelude

[9] pry(#<Hoe>)> show-doc test_prelude
# ...
Optional: Additional ruby to run before the test framework is loaded.

# Looks like I need to set RUBY_FLAGS or FILTER
[10] pry(#<Hoe>)> Hoe::RUBY_FLAGS
=> "-w -Ilib:bin:test:."
```

Wait, I remember seeing something about that in a description somewhere. Okay, looking in the source, it's part of the description. I went on exploration to figure out why it wasn't showing up. Turns out the comment that gets displayed is only the first sentence https://github.com/ruby/rake/blob/11be647a793ad06753a38cd4e1bfdac2ebd3c917/lib/rake/task.rb#L283 a bit more exploring and I discovered you can do `rake -D`, O.o wondering how many times that would have been useful to know up to this point.

At some point, I wrote down that hoe's Rakefile on line 4 seems like it should just be `require "hoe"`, given line 3. https://github.com/seattlerb/hoe/blob/215e47bb1e201ea1bef28f919393babc764e05a5/Rakefile#L3-L4

Anyway, now that I'm back looking at Hoe again (got lost for a while reading Rake code). I need to set Hoe::RUBY_FLAGS, but only if we're running the `test` task, a quick experiment to make sure Rake works the way I think it does.

```ruby
task(:test) { puts "\e[31mpre\e[0m" }
Hoe.spec "myproj" do
  task(:test) { puts "\e[31mwithin\e[0m" }
  developer("Josh Cheek", "josh.cheek@gmail.com")
  license "MIT"
end
task(:test) { puts "\e[31mpre\e[0m" }
```

Yep, so I can edit the variable in there:


```ruby
task :test do
  Hoe::RUBY_FLAGS << ' -r minitest/pride'
end

Hoe.spec "myproj" do
  developer("Josh Cheek", "josh.cheek@gmail.com")
  license "MIT"
end
```

That works, cool. Lets set the seed.

```ruby
$ rake test FILTER='-s 1234'
```

That works, too. Which is nice, but I'm pretty sure I've known something like that was generally available and just never knew how to query for that information.

Oh, I'm realizing that you can run multiple tasks at once, which would then be affected by the change to `Hoe::RUBY_FLAGS`, eg `rake test irb` would require minitest/pride when running irb. I guess you could put it into `test_globs`.

Okay, I'm going to try to congeal this into a set of coherent thoughts, and probably play with alternative ways to define the task.


## License:

```
(The MIT License)

Copyright (c) 2015 FIX

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
'Software'), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```
