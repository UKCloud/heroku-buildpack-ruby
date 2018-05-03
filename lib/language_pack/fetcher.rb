require 'yaml'
require 'language_pack/shell_helpers'

module LanguagePack
  class Fetcher
    class FetchError < StandardError; end

    include ShellHelpers
    CDN_YAML_FILE = File.expand_path('../../../config/cdn.yml', __FILE__)

    def initialize(host_url, stack = nil)
      @config   = load_config
      @host_url = fetch_cdn(host_url)
      @host_url += File.basename(stack) if stack
    end

    def fetch(path)
      path = path[1..-1] if path[0] == '/'
      curl = curl_command("-O #{@host_url.join(path)}")
      run!(curl, error_class: FetchError)
    end

    def fetch_untar(path, files_to_extract = nil)
      path = path[1..-1] if path[0] == '/'
      curl = curl_command("#{@host_url.join(path)} -s -o")
      run! "#{curl} - | tar zxf - #{files_to_extract}",
           error_class: FetchError,
           max_attempts: 3
    end

    def fetch_bunzip2(path, files_to_extract = nil)
      curl = curl_command("#{@host_url.join(path)} -s -o")
      run!("#{curl} - | tar jxf - #{files_to_extract}", error_class: FetchError)
    end

    private

    def curl_command(command)
      url, *tail = command.split(' ')

      override_url = vendor_override(url, tail)
      return override_url if override_url

      buildcurl_url = buildcurl_override(url, tail)
      return buildcurl_url if buildcurl_url

      topic "Downloading #{File.basename(url)} from: #{url}"
      'set -o pipefail; curl -L --fail --retry 5 --retry-delay 1 ' \
      "--connect-timeout #{curl_connect_timeout_in_seconds} " \
      "--max-time #{curl_timeout_in_seconds} #{command}"
    end

    def vendor_override(url, tail)
      vendor_override_mappings.each do |mapping|
        filename = File.basename(url)

        next if mapping[:name] != filename
        next if mapping[:os] && mapping[:os] != target_os

        url = vendor_override_url.join(mapping[:to])
        command = ([url] + tail).join(' ')
        topic "downloading #{filename} from: #{url}"
        return 'set -o pipefail; curl -L --fail --retry 5 --retry-delay 1 ' \
               "--connect-timeout #{curl_connect_timeout_in_seconds} " \
               "--max-time #{curl_timeout_in_seconds} #{command}"
      end
      nil
    end

    def vendor_override_mappings
      [
        {
          name: 'bundler-1.15.1.tgz',
          to: 'bundler-1.15.1.tgz'
        },
        {
          name: 'libyaml-0.1.7.tgz',
          os: 'el:7',
          to: 'el-7/libyaml-0.1.7.tgz'
        },
        {
          name: 'libyaml-0.1.7.tgz',
          os: 'ubuntu:12.04',
          to: 'ubuntu-12.04/libyaml-0.1.7.tgz'
        },
        {
          name: 'ruby-2.1.6.tgz',
          os: 'el:7',
          to: 'el-7/ruby-2.1.6.tgz'
        },
        {
          name: 'ruby-2.1.6.tgz',
          os: 'ubuntu:12.04',
          to: 'ubuntu-12.04/ruby-2.1.6.tgz'
        },
        {
          name: 'ruby-2.3.0.tgz',
          os: 'el:7',
          to: 'el-7/ruby-2.3.0.tgz'
        },
        {
          name: 'ruby-2.3.0.tgz',
          os: 'ubuntu:12.04',
          to: 'ubuntu-12.04/ruby-2.3.0.tgz'
        },
        {
          name: 'ruby-2.3.4.tgz',
          os: 'el:7',
          to: 'el-7/ruby-2.3.4.tgz'
        },
        {
          name: 'ruby-2.3.4.tgz',
          os: 'ubuntu:12.04',
          to: 'ubuntu-12.04/ruby-2.3.4.tgz'
        }
      ]
    end

    def vendor_override_url
      @vendor_override_url ||= Pathname.new(
        ENV['VENDOR_OVERRIDE_URL'] ||
          'https://github.com/jimeh/heroku-buildpack-ruby-binaries/raw/master'
      )
    end

    def buildcurl_override(url, tail)
      buildcurl_mapping = {
        'ruby' => /^ruby-(.+)$/,
        'rubygem-bundler' => /^bundler-(.+)$/,
        'libyaml' => /^libyaml-(.+)$/
      }

      buildcurl_mapping.each do |k, v|
        next unless File.basename(url, '.tgz') =~ v
        topic "Downloading #{File.basename(url)} from: buildcurl.com"
        return 'set -o pipefail; curl -L --get --fail --retry 3 ' \
               "#{buildcurl_url} " \
               "-d recipe=#{k} " \
               "-d version=#{Regexp.last_match(1)} " \
               "-d target=$TARGET #{tail.join(' ')}"
      end
      nil
    end

    def buildcurl_url
      ENV['BUILDCURL_URL'] || 'buildcurl.com'
    end

    def target_os
      @target_os ||= ENV['TARGET'].to_s
    end

    def curl_timeout_in_seconds
      env('CURL_TIMEOUT') || 30
    end

    def curl_connect_timeout_in_seconds
      env('CURL_CONNECT_TIMEOUT') || 3
    end

    def load_config
      YAML.load_file(CDN_YAML_FILE) || {}
    end

    def fetch_cdn(url)
      url = @config[url] || url
      Pathname.new(url)
    end
  end
end
