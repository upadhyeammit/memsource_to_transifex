# A placeholder for common methods for Memsource and Transifex
module Common
  def parse_json(body)
    JSON.parse(body)
  end

  def auth
    parse_json(File.read('auth.json'))
  end

  def pot_files
    Parallel.each(id_name, in_threads: 25) do |resource|
      jobs = get_jobs(resource['id'])
      Parallel.each(jobs, in_threads: 10) do |job|
        response = RestClient.get "#{@mem_api_url}projects/#{resource['id']}/jobs/#{job['uid']}/targetFile/?token=#{token}"
        puts "Saving file for resource #{resource['name']} and lang #{job['targetLang']}"
        # trim first two and last one line
        write_tx(resource['name'], job['targetLang'], response.body.lines[3..-2].join)
      end
    end
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
