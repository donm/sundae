# require 'rubygems'
require 'configatron'
require 'fileutils'
require 'find'
require 'pathname'

unless Dir.respond_to?(:home)
  class Dir
    def self.home
      File.expand_path('~')
    end
  end
end

unless Pathname.instance_methods.include?(:each_child)
  class Pathname
    def each_child(with_directory=true, &b)
      children(with_directory).each(&b)
    end
  end
end

# A collection of methods to mix the contents of several directories
# together using symbolic links.
#
module Sundae
  # :stopdoc:
  LIBPATH = ::File.expand_path(::File.dirname(__FILE__)) + ::File::SEPARATOR
  PATH = ::File.dirname(LIBPATH) + ::File::SEPARATOR
  # :startdoc:
  VERSION = ::File.read(PATH + 'version.txt').strip

  DEFAULT_CONFIG_FILE = (Pathname.new(Dir.home) + '.sundae').expand_path
 
  @config_file = DEFAULT_CONFIG_FILE

  # Read configuration from <tt>.sundae</tt>.
  #
  def self.load_config_file(config_file = DEFAULT_CONFIG_FILE)
    config_file ||= DEFAULT_CONFIG_FILE # if nil is passed
    config_file = Pathname.new(config_file).expand_path
    config_file += '.sundae' if config_file.directory?

    create_template_config_file(config_file) unless config_file.file?

    load(config_file)
    configatron.paths.map! { |p| Pathname.new(p).expand_path }

    # An array which lists the directories where mnts are stored.
    @paths = configatron.paths
    # These are the rules that are checked to see if a file in a mnt
    # should be ignored.
    @ignore_rules = configatron.ignore_rules
  end

  # Create a template configuration file at <em>config_file</em> after
  # asking the user.
  #
  def self.create_template_config_file(config_file)
    config_file = Pathname.new(config_file).expand_path
    loop do
      print "#{config_file} does not exist.  Create template there? (y/n): "
      ans = gets.downcase.strip
      if ans == "y" || ans == "yes"
        File.open(config_file, "w") do |f|
          f.puts <<-EOM.gsub(/^ {14}/, '')
              # -*-Ruby-*- 

              # An array which lists the directories where mnts are stored.
              configatron.paths = ["~/mnt"]

              # These are the rules that are checked to see if a file in a mnt
              # should be ignored.
              #
              # For `ignore_rules', use either strings (can be globs)
              # or Ruby regexps.  You can mix both in the same array.
              # Globs are matched using the method File.fnmatch.
              configatron.ignore_rules = %w(.git, 
                                            .bzr,
                                            .svn,
                                            .DS_Store)
              EOM
        end
        puts 
        puts "Okay then."
        puts "#{config_file} template created, but it needs to be customized."
        exit
      elsif ans == "n" || ans == "no"
        exit
      end
    end
  end

  # Use the array of Regexp to see if a certain file should be
  # ignored (i.e., no link will be made pointing to it).
  #
  def self.ignore_file?(file) # :doc:
    file = Pathname.new(file)
    basename = file.basename.to_s
    return true if basename =~ /^\.\.?$/
    return true if basename == ".sundae_path"
    @ignore_rules.each do |r| 
      if r.kind_of? Regexp
        return true if basename =~ r 
      else
        return true if file.fnmatch(r)
      end
    end
    return false
  end

  # Read the <tt>.sundae_path</tt> file in the root of a mnt to see
  # where in the file system links should be created for this mnt.
  #
  def self.install_location(mnt) 
    mnt = Pathname.new(mnt).expand_path
    mnt_config = mnt + '.sundae_path'
    if mnt_config.exist?
      return Pathname.new(mnt_config.readlines[0].strip).expand_path
    end

    base = mnt.basename.to_s
    match = (/dot[-_](.*)/).match(base)
    if match
      return Pathname.new(Dir.home) + ('.' + match[1])
    end

    return Pathname.new(Dir.home)
  end

  # Return an array of all paths in the file system where links will
  # be created.
  #
  def self.install_locations 
    all_mnts.map { |m| install_location(m) }.sort.uniq
  end

  # Given _path_, return all mnts (i.e., directories two levels down)
  # as an array.
  #
  def self.mnts_in_path(path) 
    Pathname.new(path).expand_path
    mnts = []
    collections = path.children(false).delete_if {|c| c.to_s =~ /^\./}

    collections.each do |c|
      collection_mnts = (path + c).children(false).delete_if {|kid| kid.to_s =~ /^\./}
      collection_mnts.map! { |mnt| (c + mnt) }

      mnts |= collection_mnts # |= is the union
    end

    return mnts.sort.uniq
  end

  # Return all mnts for every path as an array.
  #
  def self.all_mnts 
    mnts = []

    @paths.each do |path| 
      next unless path.exist?
      mnts |= mnts_in_path(path).map { |mnt| path + mnt } # |= is the union operator
    end
    return mnts
  end

  # Return all subdirectories and files in the mnts returned by
  # all_mnts.  These are the 'mirror' files and directories that are
  # generated by sundae.
  #
  def self.generated_files
    dirs = Array.new

    all_mnts.each do |mnt|
      mnt_dirs = mnt.children(false).delete_if { |e| ignore_file?(e) }
      mnt_dirs.each do |dir|
        dirs << (install_location(mnt) + dir)
      end
    end

    return dirs.sort.uniq#.select { |d| d.directory? }
  end

  # Return all subdirectories of the mnts returned by all_mnts.  These
  # are the 'mirror' directories that are generated by sundae.
  #
  def self.generated_directories 
    generated_files.select {|f| f.directory?} 
  end
  
  # Check for symlinks in the base directories that are missing their
  # targets.
  #
  def self.remove_dead_links
    install_locations.each do |location|
      next unless location.exist?
      files = location.entries.map { |f| location + f }
      files.each do |file|
        next unless file.symlink?
        next if file.readlink.exist?
        next unless root_path(file.readlink)
        file.delete 
      end
    end
  end
  
  # Search through _directory_ and return the first static file found,
  # nil otherwise.
  #
  def self.find_static_file(directory)
    directory = Pathname.new(directory).expand_path

    directory.find do |path|
      return path if path.exist? && path.ftype == 'file' 
    end
    return nil
  end

  # Delete each generated directory if there aren't any real files in
  # them.
  #
  def self.remove_generated_directories
    generated_directories.each do |dir| 
      # don't get rid of the linked config file
      next if dir.basename.to_s == '.sundae' 
      remove_generated_stuff dir

      # if sf = find_static_file(dir)
      #   puts "found static file: #{sf}"
      # else
      #   dir.rmtree
      # end
    end
  end

  def self.remove_generated_files
    generated_files.each do |fod| 
      # don't get rid of the linked config file
      next if fod.basename.to_s == '.sundae' 
      remove_generated_stuff fod
    end
  end

  def self.remove_generated_stuff(fod)
    return unless fod.exist?
    if fod.ftype == 'directory'
      fod.each_child do |c|
        remove_generated_stuff c
      end
      fod.rmdir if fod.children.empty?
    else
      return unless fod.symlink?
      fod.delete if root_path(fod.readlink) # try to only delete sundae links
    end
  end  

  # Call minimally_create_links for each mnt.
  #
  def self.create_filesystem
    all_mnts.each do |mnt|
      install_location(mnt).expand_path.mkpath
      minimally_create_links(mnt, install_location(mnt))
    end
  end

  # For each directory and file in _target_, create a link at <em>link_name</em>.  If
  # there is currently no file at <em>link_path</em>, create a symbolic link there.
  # If there is currently a symbolic link, combine the contents at the
  # link location and _target_ in a new directory and proceed
  # recursively.
  #
  def self.minimally_create_links(target, link_path) 
    target = File.expand_path(target)
    link_path = File.expand_path(link_path)

    unless File.exist?(target)
      raise "attempt to create links from missing directory: " + target
    end

    Find.find(target) do |path|
      next if path == target
      Find.prune if ignore_file?(File.basename(path))

      rel_path = path.gsub(target, '')
      link_name = File.join(link_path, rel_path)
      create_link(path, link_name)

      Find.prune if File.directory?(path) 
    end
  end

  # Starting at _dir_, walk up the directory hierarchy and return the
  # directory that is contained in _@paths_.
  #
  def self.root_path(path)
    path = Pathname.new(path).expand_path
    last = path
    path.ascend do |v|
      return last if @paths.include? v
      last = v
    end

    return nil
  end

  # Dispatch calls to create_directory_link and create_file_link.
  #
  def self.create_link(target, link_name) 
    if File.directory?(target) 
      begin
        create_directory_link(target, link_name)
      rescue => message
        puts message
      end
    elsif File.file?(target) 
      create_file_link(target, link_name)
    end
  end

  # Create a symbolic link to <em>target</em> from <em>link_name</em>.
  #
  def self.create_file_link(target, link_name) 
    raise ArgumentError, "#{target} does not exist" unless File.file?(target)
    if File.exist?(link_name)
      raise ArgumentError, "#{link_name} cannot be overwritten for #{target}." unless File.symlink?(link_name)
      if (not File.exist?(File.readlink(link_name)))
        FileUtils.ln_sf(target, link_name)
      else
        unless (File.expand_path(File.readlink(link_name)) == File.expand_path(target))
          raise ArgumentError, "#{link_name} points to #{File.readlink(link_name)}, not #{target}" unless File.symlink?(link_name)
        end
      end
    else
      FileUtils.ln_s(target, link_name)
    end
  end

  # Create a symbolic link to the directory at <em>target</em> from
  # <em>link_name</em>, unless <em>link_name</em> already exists.  In that case,
  # create a directory and recursively run minimally_create_links.
  #
  def self.create_directory_link(target, link_name) 
    raise ArgumentError unless File.directory?(target)
    if (not File.exist?(link_name)) || 
        (File.symlink?(link_name) && (not File.exist?(File.readlink(link_name))))
      FileUtils.ln_sf(target, link_name)
    else
      case File.ftype(link_name)
      when 'file'
        raise "Could not link #{link_name} to #{target}: target exists."
      when 'directory'
        minimally_create_links(target, link_name)
      when 'link'
        case File.ftype(File.readlink(link_name))
        when 'file'
          raise "Could not link #{link_name} to #{target}: another link exists there."
        when 'directory'
          combine_directories(link_name, target, File.readlink(link_name))          
        end
      end
    end
  end

  # Create a directory and create links in it pointing to
  # <em>target_path1</em> and <em>target_path2</em>.
  #
  def self.combine_directories(link_name, target_path1, target_path2) 
    raise unless File.symlink?(link_name)
    return if target_path1 == target_path2
    
    FileUtils.rm(link_name)
    FileUtils.mkdir_p(link_name)
    minimally_create_links(target_path1, link_name)
    minimally_create_links(target_path2, link_name)
  end

  def self.update_filesystem
    remove_dead_links
    remove_generated_files
    create_filesystem
  end

  def self.remove_filesystem
    remove_dead_links
    remove_generated_files
  end

  # Return an array of mnts that are installing to +path+.
  #
  def self.find_source_directories(path)
    sources = Array.new
    all_mnts.each do |mnt|
      install_location = File.expand_path(install_location(mnt))
      if path.include?(install_location)
        relative_path =  path.sub(Regexp.new(install_location), "")
        sources << mnt if File.exist?(File.join(mnt, relative_path))
      end
    end
    return sources
  end

  # Move the file at +path+ (or its target in the case of a link) to
  # +mnt+ preserving relative path.
  #
  def self.move_to_mnt(path, mnt)
    if File.symlink?(path)
      to_move = File.readlink(path)
      current = Sundae.find_source_directories(path)[0]
      relative_path = to_move.sub(Regexp.new(current), "")
      FileUtils.mv(to_move, mnt + relative_path) unless current == mnt
      FileUtils.ln_sf(mnt + relative_path, path)
    else
      location = Sundae.install_location(mnt)
      relative_path = path.sub(Regexp.new(location), "")
      FileUtils.mv(path, mnt + relative_path) unless path == mnt + relative_path
      FileUtils.ln_s(mnt + relative_path, path)
    end
  end

  # Move the target at +link+ according to +relative_path+.
  #
  def self.move_to_relative_path(link, relative_path)
    raise ArgumentError, "#{link} is not a link." unless File.symlink?(link)

    target = File.readlink(link)

    pwd = FileUtils.pwd
    mnt = Sundae.find_source_directories(link)[0]
    mnt_pwd = File.join(mnt, pwd.sub(Regexp.new(install_location(mnt)), ""))

    if File.directory?(relative_path)
      new_target_path = File.join(mnt_pwd, relative_path, File.basename(link))
      new_link_path   = File.join(pwd,     relative_path, File.basename(link))
    else
      new_target_path = File.join(mnt_pwd, relative_path)
      new_link_path   = File.join(pwd,     relative_path)   
    end

    target          = File.expand_path(target)
    new_target_path = File.expand_path(new_target_path)
    new_link_path   = File.expand_path(new_link_path)

    raise ArgumentError, "#{link} and #{new_target_path} are the same file" if target == new_target_path
    FileUtils.mkdir_p(File.dirname(new_target_path))
    FileUtils.mv(target, new_target_path)
    FileUtils.rm(link)
    FileUtils.ln_s(new_target_path, new_link_path)
  end
  
end

