# so I don't have to keep typing `ruby -I ../../lib -S rake`
local_hoe = File.expand_path '../..', __dir__
if File.basename(local_hoe) == 'hoe'
  $LOAD_PATH.unshift File.join(local_hoe, 'lib')
end

require "rubygems"
require "hoe"

# Hoe.plugin :email
# Hoe.plugin :gem_prelude_sucks
# Hoe.plugin :history
# Hoe.plugin :inline
# Hoe.plugin :isolate
# Hoe.plugin :minitest
# Hoe.plugin :seattlerb

Hoe.spec "myproj" do
  developer("Josh Cheek", "josh.cheek@gmail.com")

  license "MIT"
end
