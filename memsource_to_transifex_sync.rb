require 'rest-client'
require 'json'
require 'pry'
require 'parallel'

projects = ['foreman']
langs = ['es','fr','zh_ch','pt_br']
domainName = 'Satellite'
project_upload_date = '25-05-2020'
@resouce = RestClient::Resource.new('https://cloud.memsource.com/web/api2/v1/', :headers => { :content_type => 'application/json'})
@api_url = 'https://cloud.memsource.com/web/api2/v1/'
@work_dir = '/tmp/memsource/'
def get_token
	payload = {'userName' => 'aupadhye', 'password' => '***'}.to_json
	response = @resouce['auth/login'].post(payload)
	@token ||= parse_json(response)['token']
end

def parse_json(body)
	JSON.parse(body)
end

def get_id_name
  keys = ['id','name']
  response = RestClient.get "#{@api_url}projects/?token=#{get_token}", {:params => {'pageSize' => 50, 'domainName' => 'Satellite'}}
  projects ||= parse_json(response)["content"]
  Parallel.map(projects, in_threads:25) do |p|
  	if p['createdBy']['userName'] == 'aupadhye'
  	  p.select {|k,v| keys.include? k }
  	end
  end.compact
end

def get_jobs(pid)
  keys = ['targetLang','uid','status']
  response = RestClient.get "#{@api_url}projects/#{pid}/jobs/?token=#{get_token}"
  jobs ||= parse_json(response)["content"]
  Parallel.map(jobs, in_threads:10) do |j|
  	j.select {|k,_| keys.include? k}
  end.compact
end

def get_pot_files
  Parallel.each(get_id_name,in_threads: 25) do |project|
    jobs = get_jobs(project['id'])
  	Dir.mkdir("#{@work_dir}/#{project['name']}") if !Dir.exist?("#{@work_dir}/#{project['name']}")
  		Parallel.each(jobs, in_threads:10) do |j|
  	  	response = RestClient.get "#{@api_url}projects/#{project['id']}/jobs/#{j['uid']}/targetFile/?token=#{get_token}"
  	  	puts "Saving file for project #{project['name']} and lang #{j['targetLang']}"
  	  	f = File.new("#{@work_dir}/#{project['name']}/#{project['name']}--#{j['targetLang']}", 'w')
        # trim first two and last one line
  	  	f.write(response.body.lines[3..-2].join)
  	 end
  end
 end

get_pot_files