require 'rest-client'
require 'json'
require 'parallel'
require 'transifex'
require './common'
include Common
# Class for all vars and methods for Transifex
class TransiFex
  def initialize(langs, project_name, resource_names, work_dir)
    @project_name = project_name
    @resource_names = resource_names
    @work_dir = work_dir
    @langs = langs
    authentiate
  end

  def authentiate
    Transifex.configure do |t|
      t.client_login = auth['transifex']['username']
      t.client_secret = auth['transifex']['password']
    end
  end

  def project
    @project ||= Transifex::Project.new(@project_name)
  end

  def resources(name = [])
    return project.resource(name) if !name.empty?

    project.resources.fetch
  end

  def translation(resource, lang, file_path='')
    return resource.translation(lang).fetch_with_file(path_to_file: file_path) if !file_path.empty?

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
