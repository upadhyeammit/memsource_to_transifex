# A placeholder for common methods for Memsource and Transifex
module Common
  def self.parse_json(body)
    JSON.parse(body)
  end

  def self.auth
    parse_json(File.read('auth.json'))
  end

  def self.create_work_dir(name,filesystem = false)
    if !Dir.exist?(name)
      puts "Creating work directory for #{name}"
      Dir.mkdir(name)
    elsif !filesystem
      raise "Work directory #{name} already exist. Backup or delete the directory manually"
    end
  end
end
