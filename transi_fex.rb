require 'rest-client'
require 'json'
require 'parallel'
require 'transifex'
require './common'

# Class for all vars and methods for Transifex
class TransiFex
  LANG_MAP = {"es"=>"es", "fr"=>"fr", "ja"=>"ja", "pt_br"=>"pt_BR", "zh_cn"=>"zh_CN"}
  attr_reader :work_dir
  def initialize(work_dir, opts= {})
    @project_name = opts[:project_name]
    @resource_names = opts[:resources]
    @work_dir = work_dir+'/'+'transifex'
    @langs = opts[:langs]
    authentiate
  end

  def authentiate
    Transifex.configure do |t|
      t.client_login = Common::auth['transifex']['username']
      t.client_secret = Common::auth['transifex']['password']
    end
  end

  def project
    @project ||= Transifex::Project.new(@project_name)
  end

  def resources(name = [])
    return project.resource(name) if !name.empty?

    @resources ||= project.resources.fetch
  end

  def translation(resource, lang, file_path='')
    resource = resources(resource) if resource.is_a?(String)
    return resource.translation(lang).fetch_with_file(path_to_file: file_path) if !file_path.empty?

    resource.translation(lang).fetch
  end

  def write_tx(r_name, lang, content, filesystem)
    @project = Transifex::Project.new(@project_name)
    options = { :i18n_type => "PO", :content => content }
    begin
      @project.resource(r_name).translation(LANG_MAP[lang]).update(options)
    rescue StandardError => e
      puts e.message
      puts "** Failed to upload translation for project #{r_name} and lang #{lang}"
      if !filesystem && e.message != 'Not Found'
        unless Dir.exist?("#{@work_dir}/#{r_name}/#{lang}")
          FileUtils.mkdir_p("#{@work_dir}/#{r_name}/#{lang}")
        end
        puts "** Writing file to #{@work_dir}/#{r_name}/#{lang} for investigation"
        f = File.new("#{@work_dir}/#{r_name}/#{lang}/#{r_name}.po", 'w')
        f.write(content)
      end
    end
  end
end
