# Class for all memsource releated vars and methods
require 'rest-client'
require 'json'
require 'parallel'
require 'transifex'
require './common.rb'

class MemSource
  MEMSOURCE_API_URL = 'https://cloud.memsource.com/web/'
  DOMAIN_NAME = 'Satellite'
  PROJECT_TEMPLATE = 159694
  FILE_IMPORT_SETTINGS = 'klaukC1BdwmS5aH0mTCHD6'
  attr_reader :work_dir
  def initialize(work_dir, opts = {})
    @project_upload_date = opts[:date]#yyy-mm-dd
    @langs = opts[:langs]
    @project_names = opts[:resources]# this should be array
    @work_dir = work_dir+'/'+'memsource'
    @resouce = RestClient::Resource.new("#{MEMSOURCE_API_URL}api2/v1/", headers: { content_type: 'application/json' })
    authentiate
  end

  # @mem_api_url = 'https://cloud.memsource.com/web/api2/v1/'
  def authentiate
    payload = { 'userName' => Common::auth['memsource']['username'], 'password' => Common::auth['memsource']['password'] }.to_json
    response = @resouce['auth/login'].post(payload)
    @token ||= Common::parse_json(response)['token']
  end

  def project_ids_names(date_created = '')
    keys = %w[id name]
    response = RestClient.get "#{MEMSOURCE_API_URL}api2/v1/projects/?token=#{@token}", { params: { 'pageSize' => 50, 'domainName' => 'Satellite' } }
    projects ||= Common::parse_json(response)['content']
    Parallel.map(projects, in_threads: 25) do |p|
      if p['createdBy']['userName'] == Common::auth['memsource']['username'] && p['dateCreated'] =~ date_created
        p.select { |k, _v| keys.include? k }
      end
    end.compact
  end

  def get_jobs(pid)
    rest_client = RestClient::Resource.new("#{MEMSOURCE_API_URL}api2/v1/projects/#{pid}/jobs/?token=#{@token}")
    keys = %w[targetLang uid status]
    response = rest_client.get
    jobs ||= Common::parse_json(response)['content']
    Parallel.map(jobs, in_threads: 10) do |j|
      j.select { |k, _| keys.include? k }
    end.compact
  end

  def create_project(resource_name, template)
    rest_client = RestClient::Resource.new("#{MEMSOURCE_API_URL}api2/v2/projects/applyTemplate/#{template}?token=#{@token}", headers: { content_type: 'application/json' })
    payload = { 'name' => resource_name }.to_json
    response = rest_client.post(payload)
    JSON.parse(response.body)['uid']
  end

  def upload_locale(project_uuid, content, file_name, lang, import_settings_uid)
    metadata = "{'targetLangs': [#{lang}], 'importSettings': {'uid': #{import_settings_uid}}}"
    rest_client = RestClient::Resource.new("#{MEMSOURCE_API_URL}api2/v1/projects/#{project_uuid}/jobs?token=#{@token}", headers: {content_type: 'application/octet-stream', 'Content-Disposition': "filename=#{file_name}", 'Memsource': metadata })
    response = rest_client.post(content)
  end

  def pot_file(project_id, job_uuid)
    response = RestClient.get "#{MEMSOURCE_API_URL}api2/v1/projects/#{project_id}/jobs/#{job_uuid}/targetFile/?token=#{@token}"
    # trim first two and last one line
    response.body.lines[3..-2].join
  end

  def create_file_import_setting(name, po_regex)
    rest_client = RestClient::Resource.new("#{MEMSOURCE_API_URL}api2/v1/importSettings?token=#{@token}", headers: {content_type: 'application/json'})
    payload = {'name' => name => {'po'=> {'tagRegexp' => po_regex}}}.to_json
    response = rest_client.post(payload)
  end

  def list_file_import_settings
    rest_client = RestClient::Resource.new("#{MEMSOURCE_API_URL}api2/v1/importSettings?token=#{@token}")
    response = rest_client.get
    JSON.parse(response.body)
  end

  def delete_file_import_setting(uid)
    rest_client = RestClient::Resource.new("#{MEMSOURCE_API_URL}api2/v1/importSettings/#{uid}?token=#{@token}")
    rest_client.delete
  end
end
