gem "minitest"
require "minitest/autorun"
require "myproj"

class TestMyproj < Minitest::Test
  def test_version_matches_my_expectation
    assert_equal '1.0.0', Myproj::VERSION
  end
end
