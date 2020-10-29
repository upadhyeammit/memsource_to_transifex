# A placeholder for common methods for Memsource and Transifex
module Common
  def self.parse_json(body)
    JSON.parse(body)
  end

  def self.auth
    parse_json(File.read('auth.json'))
  end

  def self.work_dir_pot_files
    Parallel.each(Dir.children(@work_dir), in_threads: 12) do |resource|
      Parallel.each(Dir.children("#{@work_dir}/#{resource}"), in_threads: 5) do |lang|
        file_name = "#{@work_dir}/#{resource}/#{lang}"
        content = File.new(file_name)
        write_tx(resource,lang,content.read)
      end
    end
  end

  def self.create_work_dir(name)
    if !Dir.exist?(name)
      puts "Creating work directory for #{name}"
      Dir.mkdir(name)
    else
      raise "Work directory #{name} already exist. Backup or delete the directory manually"
    end
  end
end
