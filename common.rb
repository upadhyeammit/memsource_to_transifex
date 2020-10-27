# A placeholder for common methods for Memsource and Transifex
module Common
  def parse_json(body)
    JSON.parse(body)
  end

  def auth
    parse_json(File.read('auth.json'))
  end

  def work_dir_pot_files
    Parallel.each(Dir.children(@work_dir), in_threads: 12) do |resource|
      Parallel.each(Dir.children("#{@work_dir}/#{resource}"), in_threads: 5) do |lang|
        file_name = "#{@work_dir}/#{resource}/#{lang}"
        content = File.new(file_name)
        write_tx(resource,lang,content.read)
      end
    end
  end
end
