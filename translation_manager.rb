# frozen_string_literal: true
require 'clamp'
require './mem_source.rb'
require './transi_fex'
# Class to handle different commands with respect to this tool
class TransManager < Clamp::Command
  subcommand "transifex-to-memsource", 'Upload translations from Transifex to Memsource' do
    option ['--filesystem'], :flag ,'[TransiFex] Upload files from work dir. Useful after correcting pot files'
    option ['--project-name'],'','[TransiFex] Project name', required: true
    option ['--project-template'],'', '[MemSource] Project template id', default: nil
    option ['--resource-names'], '', '[TransiFex] Only work on specific resources. Comma separated list'
    option ['--lang-codes'],'','Only work on specific languages. Comma separated list', default: %w[es fr ja pt_br zh_cn]
    option ['--file-import-settings-uid'],'','File import settings if any?', default: nil
    parameter '[WORK_DIR]', 'Directory to save PO files if there is failure to upload those, useful to correct few bits and bytes', default: "/tmp/translations"

    def execute
      create_env

      @memsource = MemSource.new(work_dir, {:langs => lang_codes, :resources => resource_names, :project_template => project_template})
      @transifex = TransiFex.new(work_dir, {:langs => lang_codes, :project_name => project_name, :resources => resource_names})
      upload_to_memsource
    end
  end

  subcommand "memsource-to-transifex", 'Upload translations from Memsource to Transifex' do
    option ['--date'],'','[MemSource] (YYYY-MM-DD) Project create date on Memsource to selectively upload all projects uploaded on specific date', required: true
    option ['--filesystem'], :flag ,'[TransiFex] Upload files from work dir. Useful after correcting pot files'
    option ['--project-name'],'','[TransiFex] Project name', required: true
    option ['--lang-codes'],'','Only work on specific languages', default: %w[es fr ja pt_br zh_cn]
    parameter '[WORK_DIR]', 'Directory to save PO files if there is failure to upload those, useful to correct few bits and bytes', default: "/tmp/translations"

    def execute
      create_env
      @memsource = MemSource.new(work_dir, {:date => date, :langs => lang_codes})
      @transifex = TransiFex.new(work_dir, {:langs => lang_codes, :project_name => project_name})
      upload_to_transifex
    end
  end

  def create_env
    lang_codes = lang_codes.split(',').sort if lang_codes.is_a?(String)
    [work_dir, work_dir+'/'+'transifex',work_dir+'/'+'memsource'].each do |dir|
      Common::create_work_dir(dir,filesystem?)
    end
  end

  def upload_to_memsource
    memsource_project_uuid = {}

    if !resource_names.empty?
      tr_resources = resource_names.split(',').sort
    else
      tr_resources = @transifex.resources.map {|res| res.fetch('slug')}.sort
    end

    puts "Creating directories for #{tr_resources.join(',')}"
    # Create project directories and languages directories
    tr_resources.each do |name, _|
      project_dir = @transifex.work_dir+'/'+name
      Common::create_work_dir(project_dir)
      lang_codes.each {|lang| Common::create_work_dir(project_dir+'/'+lang)}
    end

    puts "Downloading translations for #{tr_resources.join(',')} and languages #{lang_codes.join(',')}"
    # Need to download the file and save it because transifex does not return
    # file in .po format unless file_path is provided to save it
    # Download the translation of every lang_codes_list for every resource
    tr_resources.each do |name|
      lang_codes.each do |code|
        file_path = @transifex.work_dir+'/'+name+'/'+code+'/'+name+'.po'
        @transifex.translation(name, TransiFex::LANG_MAP.fetch(code), file_path)
      end
    end

    puts "Creating #{tr_resources.join(',')} projects on MemSource"
    # Create respective projects on memsource
    tr_resources.each do |res|
      project_uuid = @memsource.create_project(res, project_template || MemSource::PROJECT_TEMPLATE)
      memsource_project_uuid[res] = project_uuid
    end

    puts "Uploading translations for #{tr_resources.join(',')}"
    # Upload the translations to memsource
    memsource_project_uuid.each do |name, uuid|
      lang_codes.each do |code|
        file_path = @transifex.work_dir+'/'+name+'/'+code+'/'+name+'.po'
        file_content = File.open(file_path,'r')
        if !file_import_settings_uid.nil?
          @memsource.upload_locale(uuid, file_content, name+'.po', TransiFex::LANG_MAP.fetch(code), file_import_settings_uid)
        else
          @memsource.upload_locale(uuid, file_content, name+'.po', TransiFex::LANG_MAP.fetch(code))
        end
      end
    end
  end

  def upload_to_transifex
    # The date is required because there can be multiple projects on memsource with same name uploaded on different dates. Which will have duplicate resources handling. The date is easy way to work on only latest translations from memsource
    # Need to change date format to regex to use with memsource api
    regx_date = Regexp.new date

    if filesystem?
      Dir.children(@transifex.work_dir).each do |resource|
        Dir.children("#{@transifex.work_dir}/#{resource}").each do |lang|
          file_name = "#{@transifex.work_dir}/#{resource}/#{lang}/#{resource}.po"
          content = File.new(file_name)
          @transifex.write_tx(resource,lang,content.read,filesystem?)
        end
      end
      return
    end

    # The memsource api returns file in po format, so we dont save it on disk before upload
    project_ids_names = @memsource.project_ids_names(regx_date)
    if project_ids_names.empty?
      raise "Can't find any projects matching with #{date} filter"
    end
    project_ids_names.each do |project|
      jobs = @memsource.get_jobs(project.fetch('id'))
      jobs.each do |job|
        translated_file = @memsource.pot_file(project.fetch('id'), job.fetch('uid'))
        if lang_codes.include?(job.fetch('targetLang'))
          puts "Uploading file for project #{project.fetch('name')} and for lang #{job.fetch('targetLang')}"
          @transifex.write_tx(project.fetch('name'), job.fetch('targetLang'), translated_file, filesystem?)
        end
      end
    end
  end
end

TransManager.run
