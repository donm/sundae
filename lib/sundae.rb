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
      line = mnt_config.readlines[0]
      if line then
        return Pathname.new(line.strip).expand_path
      end
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
    collections = path.children.delete_if {|c| c.basename.to_s =~ /^\./}

    return collections.map do |c|
      unless c.exist?
        warn("Skipping mnt: #{c}")
        next
      end
      if c.children(false).include? Pathname.new('.sundae_path')
        c
      else
        collection_mnts = c.children.delete_if {|kid| kid.basename.to_s =~ /^\./}
        # collection_mnts.keep_if { |k| (path + c + k).directory? }
        collection_mnts.reject! { |k| ! (path + c + k).directory? }
        collection_mnts.map! { |mnt| (c + mnt) }
      end
    end.flatten.compact.sort.uniq
  end

  # Return all mnts for every path as an array.
  #
  def self.all_mnts 
    @all_mnts ||= @paths.map do |path| 
      unless path.exist?
        warn "Path doesn't exist: #{path}"
        next
      end
      mnts_in_path(path)
    end.compact.flatten
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
        next if file.exist?
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

  # # Delete each generated directory if there aren't any real files in
  # # them.
  # #
  # def self.remove_generated_directories
  #   generated_directories.each do |dir| 
  #     # don't get rid of the linked config file
  #     next if dir.basename.to_s == '.sundae' 
  #     remove_generated_stuff dir

  #     # if sf = find_static_file(dir)
  #     #   puts "found static file: #{sf}"
  #     # else
  #     #   dir.rmtree
  #     # end
  #   end
  # end

  def self.remove_generated_files
    generated_files.each do |fod| 
      # don't get rid of the linked config file
      next if fod.basename.to_s == '.sundae' 
      remove_generated_stuff fod
    end
  end

  def self.remove_generated_stuff(fod)
    return unless fod.exist? || fod.symlink?
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

  # For each directory and file in _old_, create a link at <em>link_name</em>.  If
  # there is currently no file at <em>new</em>, create a symbolic link there.
  # If there is currently a symbolic link, combine the contents at the
  # link location and _old_ in a new directory and proceed
  # recursively.
  #
  def self.minimally_create_links(old, new) 
    old    = Pathname.new(old)
    new = Pathname.new(new)

    unless old.exist?
      raise "attempt to create links from missing directory: " + old
    end

    old.realpath.find do |path|
      next if path == old.realpath
      Find.prune if ignore_file?(File.basename(path))

      rel_path = path.relative_path_from(old.realpath)
      link_name = new + rel_path

#      puts "#{link_name} -> #{old + rel_path}"
      create_link(old + rel_path, link_name)

      Find.prune if path.directory?
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
  def self.create_link(old, new) 
    old    = Pathname.new(old)
    new = Pathname.new(new)

    if old.directory?
      begin
        create_directory_link(old, new)
      rescue => message
        puts message
      end
    elsif old.file?
      create_file_link(old, new)
    end
  end

  # Create a symbolic link to <em>old</em> from <em>new</em>.
  #
  def self.create_file_link(old, new) 
    old = Pathname.new(old)
    new = Pathname.new(new)

    raise ArgumentError, "#{old} does not exist" unless old.file? || old.symlink?
    if new.symlink?
      raise ArgumentError, "#{new.to_s} cannot be overwritten for #{old}: points to #{new.readlink.to_s}" unless new.readlink.to_s == old.to_s
    else
      raise ArgumentError, "#{new} cannot be overwritten for #{old}." if new.exist?
      new.make_symlink(old)
    end
  end

  # Create a symbolic link to the directory at <em>old</em> from
  # <em>new</em>, unless <em>new</em> already exists.  In that case,
  # create a directory and recursively run minimally_create_links.
  #
  def self.create_directory_link(old, new) 
    old = Pathname.new(old)
    new = Pathname.new(new)

    raise ArgumentError unless old.directory?
    if not new.exist? || new.symlink?
      new.make_symlink(old)
    else
      case new.ftype
      when 'file'
        raise "Could not link #{new} to #{old}: old exists."
      when 'directory'
        minimally_create_links(old, new)
      when 'link'
        case new.realpath.ftype
        when 'file'
          raise "Could not link #{new} to #{old}: another link exists there."
        when 'directory'
          combine_directories(old, new.readlink, new)   
        end
      end
    end
  end

  # Create a directory and create links in it pointing to
  # <em>old1</em> and <em>old2</em>.
  #
  def self.combine_directories(old1, old2, new) 
    new = Pathname.new(new)
    old1 = Pathname.new(old1).expand_path
    old2 = Pathname.new(old2).expand_path

    raise "combine_directories in #{new}" unless new.symlink?
    return if old1 == old2
    
    new.delete
    new.mkpath
    minimally_create_links(old1, new)
    minimally_create_links(old2, new)
  end

  def self.update_filesystem
    remove_filesystem
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

