require 'yaml'
require 'language_pack/shell_helpers'

module LanguagePack
  class Fetcher
    class FetchError < StandardError; end

    include ShellHelpers
    CDN_YAML_FILE = File.expand_path('../../config/cdn.yml', __dir__)

    OVERRIDE_VENDOR_URL = 'https://github.com/jimeh/' \
                          'heroku-buildpack-ruby-binaries/' \
                          'raw/master'.freeze
    OVERRIDE_VENDOR_MAPPING = {
      'bundler-1.15.1.tgz' => 'bundler-1.15.1.tgz',
      'libyaml-0.1.7.tgz' => 'libyaml-0.1.7.tgz',
      'ruby-2.1.6.tgz' => 'ruby-2.1.6.tgz',
      'ruby-2.3.0.tgz' => 'ruby-2.3.0.tgz',
      'ruby-2.3.4.tgz' => 'ruby-2.3.4.tgz'
    }.freeze

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
      binary, *rest = command.split(' ')

      OVERRIDE_VENDOR_MAPPING.each do |k, v|
        filename = File.basename(binary)
        next unless filename.match(k)

        binary = override_vendor_url.join(v)
        command = ([binary] + rest).join(' ')
        topic "Downloading #{filename} from: #{binary}"
        return "set -o pipefail; curl -L --fail --retry 5 --retry-delay 1 --connect-timeout #{curl_connect_timeout_in_seconds} --max-time #{curl_timeout_in_seconds} #{command}"
      end

      buildcurl_mapping = {
        'ruby' => /^ruby-(.+)$/,
        'rubygem-bundler' => /^bundler-(.+)$/,
        'libyaml' => /^libyaml-(.+)$/
      }
      buildcurl_mapping.each do |k, v|
        if File.basename(binary, '.tgz') =~ v
          topic "Downloading #{File.basename(binary)} from: buildcurl.com"
          return "set -o pipefail; curl -L --get --fail --retry 3 #{buildcurl_url} -d recipe=#{k} -d version=#{Regexp.last_match(1)} -d target=$TARGET #{rest.join(' ')}"
        end
      end

      topic "Downloading #{File.basename(binary)} from: #{binary}"
      "set -o pipefail; curl -L --fail --retry 5 --retry-delay 1 --connect-timeout #{curl_connect_timeout_in_seconds} --max-time #{curl_timeout_in_seconds} #{command}"
    end

    def buildcurl_url
      ENV['BUILDCURL_URL'] || 'buildcurl.com'
    end

    def override_vendor_url
      @override_vendor_url ||= Pathname.new(
        ENV['OVERRIDE_VENDOR_URL'] || OVERRIDE_VENDOR_URL
      )
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
