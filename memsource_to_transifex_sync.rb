# frozen_string_literal: true

require 'rest-client'
require 'json'
require 'parallel'
require 'transifex'

@project = 'test-foreman'
domainName = 'Satellite'
@project_upload_date = /2020-07-02/ #yyy-mm-dd
@mem_api_url = 'https://cloud.memsource.com/web/api2/v1/'
@tran_api_url = 'https://www.transifex.com/api/2/'

@resouce = RestClient::Resource.new(@mem_api_url.to_s, headers: { content_type: 'application/json' })
@work_dir = '/tmp/memsource/'

def parse_json(body)
  JSON.parse(body)
end

def auth
  parse_json(File.read('auth.json'))
end

Transifex.configure do |c|
  c.client_login = auth['transifex']['username']
  c.client_secret = auth['transifex']['password']
end

def token
  payload = { 'userName' => auth['memsource']['username'], 'password' => auth['memsource']['password'] }.to_json
  response = @resouce['auth/login'].post(payload)
  @token ||= parse_json(response)['token']
end

def id_name
  keys = %w[id name]
  response = RestClient.get "#{@mem_api_url}projects/?token=#{token}", { params: { 'pageSize' => 50, 'domainName' => 'Satellite' } }
  projects ||= parse_json(response)['content']
  Parallel.map(projects, in_threads: 25) do |p|
    if p['createdBy']['userName'] == auth['memsource']['username'] && p['dateCreated'] =~ @project_upload_date
      p.select { |k, _v| keys.include? k }
    end
  end.compact
end

def get_jobs(pid)
  keys = %w[targetLang uid status]
  response = RestClient.get "#{@mem_api_url}projects/#{pid}/jobs/?token=#{token}"
  jobs ||= parse_json(response)['content']
  Parallel.map(jobs, in_threads: 10) do |j|
    j.select { |k, _| keys.include? k }
  end.compact
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

def write_tx(r_name, lang, content)
  lang_map = { 'ja' => 'ja', 'es' => 'es', 'fr' => 'fr', 'zh_cn' => 'zh_CN', 'pt_br' => 'pt_BR' }
  @project = Transifex::Project.new('test-foreman')
  options = { :i18n_type => "PO", :content => content }
  begin
    @project.resource(r_name).translation(lang_map[lang]).update(options)
  rescue StandardError => e
    puts e.message
    puts "** Failed to upload translation for project #{r_name} and lang #{lang}"
    if @mode == 'memsource'
      unless Dir.exist?("#{@work_dir}/#{r_name}")
        Dir.mkdir("#{@work_dir}/#{r_name}")
      end
      puts "** Writing file to #{@work_dir}/#{r_name}/#{lang} for investigation"
      f = File.new("#{@work_dir}/#{r_name}/#{lang}", 'w')
      f.write(content)
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

if ARGV[0] == 'filesystem'
  @mode = 'filesystem'
  work_dir_pot_files
else
  @mode = 'memsource'
  pot_files
end