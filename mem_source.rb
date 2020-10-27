# Class for all memsource releated vars and methods
require 'rest-client'
require 'json'
require 'parallel'
require 'transifex'
require './common.rb'
include Common

class MemSource
  MEMSOURCE_API_URL = 'https://cloud.memsource.com/web/'
  DOMAIN_NAME = 'Satellite'
  PROJECT_TEMPLATE = 159694
  def initialize(date, langs, resource_names, work_dir)
    @project_upload_date = date #yyy-mm-dd
    @langs = langs
    @project_names = resource_names # this should be array
    @work_dir = work_dir
    @resouce = RestClient::Resource.new("#{MEMSOURCE_API_URL}api2/v1/", headers: { content_type: 'application/json' })
    authentiate
  end

  # @mem_api_url = 'https://cloud.memsource.com/web/api2/v1/'
  def authentiate
    payload = { 'userName' => auth['memsource']['username'], 'password' => auth['memsource']['password'] }.to_json
    response = @resouce['auth/login'].post(payload)
    @token ||= parse_json(response)['token']
  end

  def project_ids_names(date_created = '')
    keys = %w[id name]
    response = RestClient.get "#{MEMSOURCE_API_URL}/api2/v1/projects/?token=#{@token}", { params: { 'pageSize' => 50, 'domainName' => 'Satellite' } }
    projects ||= parse_json(response)['content']
    Parallel.map(projects, in_threads: 25) do |p|
      if p['createdBy']['userName'] == auth['memsource']['username'] && p['dateCreated'] =~ date_created
        p.select { |k, _v| keys.include? k }
      end
    end.compact
  end

  def get_jobs(pid)
    rest_client = RestClient::Resource.new("#{MEMSOURCE_API_URL}api2/v1/projects/#{pid}/jobs/?token=#{@token}")
    keys = %w[targetLang uid status]
    response = rest_client.get
    jobs ||= parse_json(response)['content']
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

  def upload_locale(project_uuid, content, file_name, lang)
    rest_client = RestClient::Resource.new("#{MEMSOURCE_API_URL}api2/v1/projects/#{project_uuid}/jobs?token=#{@token}", headers: {content_type: 'application/octet-stream', 'Content-Disposition': "filename=#{file_name}", 'Memsource': "{'targetLangs': [#{lang}]}" })
    response = rest_client.post(content)
  end

  def pot_file(project_id, job_uuid)
    response = RestClient.get "#{MEMSOURCE_API_URL}/api2/v1/projects/#{project_id}/jobs/#{job_uuid}/targetFile/?token=#{@token}"
    # trim first two and last one line
    response.body.lines[3..-2].join)
  end

end
