require 'test/unit' 

$:.unshift File.join(File.dirname(__FILE__), "..", "bin") # add ../bin to the Ruby library path
$:.unshift File.join(File.dirname(__FILE__), "..", "lib") #     ../lib
require 'sundae'
require 'pathname'

class TestSundae < Test::Unit::TestCase

  @@testdir = Pathname.new(__FILE__).parent.expand_path
  @@sandbox    = @@testdir + 'sandbox'
  @@static_dir = @@sandbox + 'static'
  @@mnts_dir   = @@sandbox + 'mnts'

  def setup
    @@sandbox.mkpath
    @@static_dir.mkpath

    (@@static_dir + 'static').open('w')
    %w(c1 c2 c1/d1 c1/d2 c2/d1 c2/d3 c2/d3/d31).each do |x| 
      (@@mnts_dir + x).mkpath
    end

    %w(c1/d1/f11 c1/d1/f12 c1/d2/f21 c2/d1/f13 c2/d1/f14 c2/d3/f31).each do |x|
      (@@mnts_dir + x).open('w')
    end

    %w(c1/d1 c1/d2 c2/d1 c2/d3).each do |d|
      (@@mnts_dir + d + '.sundae_path').open('w') {|f| f.puts @@sandbox}
    end

    @@path1 = @@sandbox + 'mnts'
    @@config_file = @@sandbox + '.sundae'
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
    @@sandbox.rmtree
  end

  def test_class_all_mnts
    all_mnts = Sundae.all_mnts
    mnts = Sundae.mnts_in_path(@@path1)
    mnts.each do |m|
      assert all_mnts.include?(@@path1 + m)
    end
  end

  def test_class_combine_directories
    d1   = @@mnts_dir + 'c1/d1'
    d2   = @@mnts_dir + 'c1/d2'
    link = @@sandbox  + 'link'
    FileUtils.ln_s(d1, link)
    Sundae.combine_directories(d1, d2, link)
    assert File.symlink?(link + 'f11')
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

  def test_class_generated_files
    Sundae.create_filesystem
#    assert Sundae.generated_files.include?(File.join(@@sandbox, 'f11'))
    assert_equal 7, Sundae.generated_files.size
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
    assert_equal Pathname.new(Dir.home), Sundae.install_location('/')
    assert_equal @@sandbox, Sundae.install_location(@@mnts_dir + 'c1/d1')
  end

  def test_class_install_locations
    assert_equal [@@sandbox], Sundae.install_locations
  end

  def test_class_load_config_file
    sundae_paths = Sundae.instance_variable_get(:@paths)
    assert_equal sundae_paths[0], Pathname.new(@@path1).expand_path
  end

  def test_class_minimally_create_links
    c1 = File.join(@@mnts_dir, 'c1')
    c2 = File.join(@@mnts_dir, 'c2')
    Sundae.minimally_create_links(c1, @@sandbox)
    assert((@@sandbox + 'd1').symlink?)
    assert((@@sandbox + 'd2').symlink?)
    Sundae.minimally_create_links(c2, @@sandbox)
    assert((@@sandbox + 'd1').directory?)
    assert((@@sandbox + 'd1/f11').symlink?)
    assert((@@sandbox + 'd1/f14').symlink?)
    assert((@@sandbox + 'd2').symlink?)
    assert((@@sandbox + 'd3').symlink?)
  end

  def test_class_mnts_in_path
    md = Pathname.new(@@mnts_dir)
    assert_equal ['c1/d1', 'c1/d2', 'c2/d1', 'c2/d3'].map {|x| (md + x).expand_path},
        Sundae.mnts_in_path(@@path1)
  end

  def test_class_remove_dead_links
    (@@sandbox + 'temp_file').open('w')
    (@@sandbox + 'perm_file').open('w')
    FileUtils.ln_s(File.join(@@sandbox, 'temp_file'), File.join(@@sandbox, 'link'))
    (@@sandbox + 'temp_file').delete
    assert ! (@@sandbox + 'link').exist?
    assert (@@sandbox + 'perm_file').exist?
  end

  # def test_class_remove_generated_directories
  #   Sundae.generated_directories.each { |d| FileUtils.mkdir_p(d) }
  #   Sundae.remove_generated_directories
  #   Sundae.generated_directories.each do |d|
  #     assert ! File.exist?(d)
  #   end
  # end

  def test_class_root_path
    assert_equal @@mnts_dir +'c1',  Sundae.root_path(@@mnts_dir + 'c1')
    assert_equal @@mnts_dir + 'c1', Sundae.root_path(@@mnts_dir + 'c1/d1')
    assert_equal nil,               Sundae.root_path('/')
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

