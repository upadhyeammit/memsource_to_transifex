# frozen_string_literal: true
require 'clamp'
require 'rest-client'
require 'json'
require 'parallel'
require 'transifex'

# Class to handle different commands with respect to this tool
class TransManager < Clamp::Command
  option ['-t', '--transifex-to-memsource'], :flag, 'Upload translations from Transifex to Memsource'
  option ['-m', '--memsource-to-transifex'], :flag, 'Upload translations from Memsource to Transifex'
  parameter '[DATE]', 'DATE', 'Project create date on Memsource to selectively upload all projects uploaded on specific date'
  parameter '[WORK_DIR]', 'Directory to save PO files if there is failure to upload those, useful to correct few bits and bytes', default: "/tmp/translations"
  parameter '[RESOURCE_NAMES]', 'Only work on specific resources', default: [], multivalued: true
  parameter '[project_name]', 'Project name for Transifex'
  parameter '[LANGS]', 'Only work on specific languages', default: %w[ja es fr zh_cn pt_br], multivalued: true

  def execute
    Memsource.new(date, langs, resource_names, work_dir) if transifex_to_memsource?
    Transifex.new(langs, project_name, resource_names, work_dir) if memsource_to_transifex?
  end
end

TransManager.run

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


# Class for all memsource releated vars and methods
class Memsource
  MEMSOURCE_API_URL = 'https://cloud.memsource.com/web/api2/v1/'
  DOMAIN_NAME = 'Satellite'

  def initilize(date, project_names, work_dir)
    @project_upload_date = date #yyy-mm-dd
    @project_names = project_names # this should be array
    @work_dir = work_dir
    @resouce = RestClient::Resource.new(MEMSOURCE_API_URL.to_s, headers: { content_type: 'application/json' })
  end

  # @mem_api_url = 'https://cloud.memsource.com/web/api2/v1/'
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
end

# Class for all vars and methods for Transifex
class Transifex
  @tran_api_url = 'https://www.transifex.com/api/2/'
  
  def init(langs, project_name, resource_names, work_dir)
    Transifex.configure do |c|
      c.client_login = auth['transifex']['username']
      c.client_secret = auth['transifex']['password']
    end
    @project = project_name 
    @resource_names = resource_names
    @work_dir = work_dir
    @langs = langs
  end

  def project
    Transifex::Project.new(@project)
  end

  def resources(name = [])
    return project.resource(name) if !name.empty?
    
    project.resources.fetch
  end

  def translation(resource, lang, with_file = false)
    return resource.translation(lang).fetch_with_file if with_file
    
    resource.translation(lang).fetch
  end

  def write_tx(r_name, lang, content)
    lang_map = { 'ja' => 'ja', 'es' => 'es', 'fr' => 'fr', 'zh_cn' => 'zh_CN', 'pt_br' => 'pt_BR' }
    @project = Transifex::Project.new('foreman')
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
end

