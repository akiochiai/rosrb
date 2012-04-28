require 'rexml/document'

module ROS
  # Load package file and add paths to depending packages.
  # This method should be called before creating any node.
  def self.load_manifest(package_name, use_rospack_cache=true)
    cache_found = false
    if use_rospack_cache and ENV.has_key?('ROS_ROOT')
      cache_path = File.join(ENV['ROS_ROOT'], ".rospack_cache")
      if File.exist?(cache_path) and File.file?(cache_path)
        cache_file = File.new(cache_path, 'r')
        cache_file.each_line do |line|
          pkg_name = File.basename(line)
          @@ROS_PACKAGE_PATH[pkg_name] = line
        end
        cache_found = true
      end
    end
    if not cache_found
      ros_pkg_path = ENV['ROS_PACKAGE_PATH'] or ""
      search_paths = ros_pkg_path.split(":")
      search_paths.unshift(ENV['ROS_ROOT']) if ENV.has_key?('ROS_ROOT')
      while search_paths.length > 0
        path = search_paths.pop
        next unless File.exist?(path)
        next unless File.directory?(path)
        next if File.symlink?(path)
        next if File.basename(path) == ".."
        next if File.basename(path) == "."

        entries = Dir.entries(path).map { |e| File.join(path, e) }
        manifest = entries.any? do |e|
          File.file?(e) and File.basename(e) == "manifest.xml"
        end
        if manifest
          @@ROS_PACKAGE_CACHE[File.basename(path)] = File.absolute_path(path)
        else
          search_paths += entries
        end
      end
    end

    depends = [package_name]
    while depends.length > 0
      pkg = depends.pop
      pkg_dir = @@ROS_PACKAGE_CACHE[pkg]
      manifest = File.join(pkg_dir, 'manifest.xml')
      $LOAD_PATH.unshift(File.join(pkg_dir, 'src'))
      $LOAD_PATH.unshift(File.join(pkg_dir, 'lib'))
      file = File.new(manifest, 'r')
      dom = REXML::Document.new(file)
      dom.root.elements.each("depend") do |depend|
        depend_pkg = depend.attributes["package"]
        depends.push(depend_pkg)
      end
      dom.root.elements.each("export") do |export|
        export.elements.each("ruby") do |ruby|
          path = ruby.attributes["path"]
          path.gsub!("${prefix}", @@ROS_PACKAGE_CACHE[pkg])
          $LOAD_PATH.unshift(path)
        end
      end
    end
    $LOAD_PATH
  end

  private

  @@ROS_PACKAGE_CACHE = {}
end # module ROS
