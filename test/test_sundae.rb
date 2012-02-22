require 'test/unit' 

$:.unshift File.join(File.dirname(__FILE__), "..", "bin") # add ../bin to the Ruby library path
$:.unshift File.join(File.dirname(__FILE__), "..", "lib") #     ../lib
require 'sundae'

class TestSundae < Test::Unit::TestCase

  @@testdir = File.dirname(File.expand_path(__FILE__))
  @@sandbox = File.join(@@testdir, 'sandbox')
  @@static_dir = File.join(@@sandbox, 'static')
  @@mnts_dir = File.join(@@sandbox, 'mnts')

  def setup
    FileUtils.mkdir_p(@@sandbox)

    FileUtils.mkdir_p(@@static_dir)
    File.open(File.join(@@static_dir, 'static'), 'w')
    FileUtils.mkdir_p(File.join(@@mnts_dir, 'c1'))
    FileUtils.mkdir_p(File.join(@@mnts_dir, 'c2'))
    FileUtils.mkdir_p(File.join(@@mnts_dir, 'c1/d1'))
    FileUtils.mkdir_p(File.join(@@mnts_dir, 'c1/d2'))
    FileUtils.mkdir_p(File.join(@@mnts_dir, 'c2/d1'))
    FileUtils.mkdir_p(File.join(@@mnts_dir, 'c2/d3'))
    FileUtils.mkdir_p(File.join(@@mnts_dir, 'c2/d3/d31'))
    File.open(File.join(@@mnts_dir, 'c1/d1/f11'), 'w')
    File.open(File.join(@@mnts_dir, 'c1/d1/f12'), 'w')
    File.open(File.join(@@mnts_dir, 'c1/d2/f21'), 'w')
    File.open(File.join(@@mnts_dir, 'c2/d1/f13'), 'w')
    File.open(File.join(@@mnts_dir, 'c2/d1/f14'), 'w')
    File.open(File.join(@@mnts_dir, 'c2/d3/f31'), 'w')
    ['c1/d1', 'c1/d2', 'c2/d1', 'c2/d3'].each do |d|
      File.open(File.join(@@mnts_dir, d, '.sundae_path'), 'w') do |f|
        f.puts @@sandbox
      end
    end

    @@path1 = File.join(@@sandbox, 'mnts')

    @@config_file = File.join(@@sandbox, ".sundae")
    File.open(@@config_file, 'w+') do |f|
      f.puts "configatron.paths = [\"#{@@path1}\"]"
      f.puts "configatron.ignore_rules = %w("
      f.puts "  .svn"
      f.puts "  *.git"
      f.puts "  .DS_Store) << /bzr/"
    end
    Sundae.load_config_file(@@sandbox)
  end

  def teardown
    FileUtils.rm_r(@@sandbox)
  end

  def test_class_all_mnts
    all_mnts = Sundae.all_mnts
    mnts = Sundae.mnts_in_path(@@path1)
    mnts.each do |m|
      assert all_mnts.include?(File.join(@@path1,m))
    end
  end

  def test_class_combine_directories
    d1 = File.join(@@mnts_dir, 'c1/d1')
    d2 = File.join(@@mnts_dir, 'c1/d2')
    link = File.join(@@sandbox, 'link')
    FileUtils.ln_s(d1, link)
    Sundae.combine_directories(link, d1, d2)
    assert File.symlink?(File.join(link, 'f11'))
  end

  def test_class_create_directory_link
    assert_nothing_raised do
      Sundae.create_directory_link(File.join(@@mnts_dir, 'c1/d1'), File.join(@@sandbox, 'new_link'))
      assert File.symlink?(File.join(@@sandbox, 'new_link'))
    end
    assert_raise ArgumentError do
      Sundae.create_directory_link(File.join(@@mnts_dir, 'non_existent_directory'), File.join(@@sandbox, 'new_link4'))
    end
    assert_raise ArgumentError do
      Sundae.create_directory_link(File.join(@@mnts_dir, 'c1/d1/f11'), File.join(@@sandbox, 'new_link4'))
    end
  end

  def test_class_create_file_link
    assert_nothing_raised do
      Sundae.create_file_link(File.join(@@mnts_dir, 'c1/d1/f11'), File.join(@@sandbox, 'new_link'))
      assert File.symlink?(File.join(@@sandbox, 'new_link'))
    end
    assert_nothing_raised do
      FileUtils.ln_s(File.join(@@mnts_dir, 'c1/d1/f11'), File.join(@@sandbox, 'new_link2'))
      Sundae.create_file_link(File.join(@@mnts_dir, 'c1/d1/f11'), File.join(@@sandbox, 'new_link2'))
    end
    assert_raise ArgumentError do
      File.open(File.join(@@sandbox, 'new_link3'), 'w')
      Sundae.create_file_link(File.join(@@mnts_dir, 'c1/d1/f11'), File.join(@@sandbox, 'new_link3'))
    end
    assert_raise ArgumentError do
      FileUtils.ln_s(File.join(@@mnts_dir, 'd1'), File.join(@@sandbox, 'new_link4'))
      Sundae.create_file_link(File.join(@@mnts_dir, 'd1'), File.join(@@sandbox, 'new_link4'))
    end
    assert_raise ArgumentError do
      Sundae.create_file_link(File.join(@@mnts_dir, 'c1/d1'), File.join(@@sandbox, 'new_link4'))
    end
  end

  def test_class_create_filesystem
    Sundae.create_filesystem
    assert File.symlink?(File.join(@@sandbox, 'f11'))
    assert File.symlink?(File.join(@@sandbox, 'f31'))
  end

  def test_class_find_static_file
    10.times do
      assert_not_nil Sundae.find_static_file(@@mnts_dir)
      FileUtils.rm(Sundae.find_static_file(@@mnts_dir))
    end
    assert_nil Sundae.find_static_file(@@mnts_dir)
  end

  def test_class_generated_directories
    Sundae.create_filesystem
    assert_kind_of Array, Sundae.generated_directories
    assert !Sundae.generated_directories.include?(File.join(@@sandbox, 'f11'))
    assert_equal 1, Sundae.generated_directories.size
  end

  def test_class_ignore_file_eh
    assert Sundae.ignore_file?('.sundae_path')
    assert Sundae.ignore_file?('..')
    assert Sundae.ignore_file?(".svn")
    assert Sundae.ignore_file?("arst.git")
    assert Sundae.ignore_file?(".bzrarst")
    assert_equal Sundae.ignore_file?('normal_file.txt'), false
  end

  def test_class_install_location
    assert_equal Sundae.install_location('/'), ENV['HOME']
    assert_equal Sundae.install_location(File.join(@@mnts_dir, 'c1/d1')), @@sandbox
  end

  def test_class_install_locations
    assert_equal Sundae.install_locations, [@@sandbox]
  end

  def test_class_load_config_file
    sundae_paths = Sundae.instance_variable_get(:@paths)
    assert_equal sundae_paths[0], File.expand_path(@@path1)
  end

  def test_class_minimally_create_links
    c1 = File.join(@@mnts_dir, 'c1')
    c2 = File.join(@@mnts_dir, 'c2')
    Sundae.minimally_create_links(c1, @@sandbox)
    assert File.symlink?(File.join(@@sandbox, 'd1'))
    assert File.symlink?(File.join(@@sandbox, 'd2'))
    Sundae.minimally_create_links(c2, @@sandbox)
    assert File.directory?(File.join(@@sandbox, 'd1'))
    assert File.symlink?(File.join(@@sandbox, 'd1/f11'))
    assert File.symlink?(File.join(@@sandbox, 'd1/f14'))
    assert File.symlink?(File.join(@@sandbox, 'd2'))
    assert File.symlink?(File.join(@@sandbox, 'd3'))
  end

  def test_class_mnts_in_path
    assert_equal Sundae.mnts_in_path(@@path1), ['c1/d1', 'c1/d2', 'c2/d1', 'c2/d3']
  end

  def test_class_remove_dead_links
    File.open(File.join(@@sandbox, 'temp_file'), 'w')
    File.open(File.join(@@sandbox, 'perm_file'), 'w')
    FileUtils.ln_s(File.join(@@sandbox, 'temp_file'), File.join(@@sandbox, 'link'))
    FileUtils.rm(File.join(@@sandbox, 'temp_file'))
    assert_equal Sundae.remove_dead_links, [File.join(@@sandbox, 'link')]
    assert ! File.exist?(File.join(@@sandbox, 'link'))
    assert File.exist?(File.join(@@sandbox, 'perm_file'))
  end

  def test_class_remove_generated_directories
    Sundae.generated_directories.each { |d| FileUtils.mkdir_p(d) }
    Sundae.remove_generated_directories
    Sundae.generated_directories.each do |d|
      assert ! File.exist?(d)
    end
  end

  def test_class_root_path
    assert_equal Sundae.root_path(File.join(@@mnts_dir, 'c1')), File.join(@@mnts_dir, 'c1')
    assert_equal Sundae.root_path(File.join(@@mnts_dir, 'c1/d1')), File.join(@@mnts_dir, 'c1')

    assert_raise ArgumentError do
      Sundae.root_path('/')
    end
  end

  def test_class_create_link
      Sundae.create_link(File.join(@@mnts_dir, 'c1/d1/f11'), File.join(@@sandbox, 'new_link1'))
      assert File.symlink?(File.join(@@sandbox, 'new_link1'))
      Sundae.create_link(File.join(@@mnts_dir, 'c1/d1'), File.join(@@sandbox, 'new_link2'))
      assert File.symlink?(File.join(@@sandbox, 'new_link2'))
  end

  def test_class_create_template_config_file
    assert "I'm happy not testing this right now"
  end

end

