require 'json'
require 'fleet/connection'
require 'fleet/error'
require 'fleet/request'
require 'fleet/service_definition'
require 'fleet/client/job'
require 'fleet/client/state'
require 'fleet/client/unit'

module Fleet
  class Client

    FLEET_PATH = 'v2/keys/_coreos.com/fleet'
    MAX_RETRIES = 10
    SLEEP_TIME = (1.0 / 10.0)

    attr_accessor(*Configuration::VALID_OPTIONS_KEYS)

    def initialize(options={})
      options = Fleet.options.merge(options)
      Configuration::VALID_OPTIONS_KEYS.each do |key|
        send("#{key}=", options[key])
      end
    end

    include Fleet::Connection
    include Fleet::Request

    include Fleet::Client::Job
    include Fleet::Client::State
    include Fleet::Client::Unit

    def load(name, service_def={})

      unless service_def.is_a?(ServiceDefinition)
        service_def = ServiceDefinition.new(name, service_def)
      end

      begin
        create_unit(service_def.sha1, service_def.to_unit)
      rescue Fleet::PreconditionFailed
      end

      begin
        create_job(service_def.name, service_def.to_job)
      rescue Fleet::PreconditionFailed
      end

      update_job_target_state(service_def.name, :loaded)
      wait_for_load_state(service_def.name, 'loaded')
    end

    def start(service_name)
      update_job_target_state(service_name, :launched)
    end

    def stop(service_name)
      update_job_target_state(service_name, :loaded)
      wait_for_load_state(service_name, 'loaded')
    end

    def unload(service_name)
      update_job_target_state(service_name, :inactive)
      wait_for_load_state(service_name, 'not-found')
    end

    def destroy(service_name)
      delete_job(service_name)
      wait_for_load_state(service_name, :no_state)
    end

    def status(service_name)
      fleet_state = get_state(service_name)
      service_states = JSON.parse(fleet_state['node']['value'])
      service_states.each_with_object({}) do |(k, v), hash|
        hash[underscore(k).to_sym] = v
      end
    end

    protected

    def resource_path(resource, *parts)
      parts.unshift(resource).unshift(FLEET_PATH).join('/')
    end

    def wait_for_load_state(service_name, target_state='loaded')
      result = MAX_RETRIES.times do
        begin
          break target_state if status(service_name)[:load_state] == target_state
        rescue Fleet::NotFound
          # :no_state is a special case of target state that indicates we
          # expect the state to not be found at all (useful when waiting for
          # a delete job call)
          break target_state if target_state == :no_state
        end

        sleep(SLEEP_TIME)
      end

      if result == target_state
        true
      else
        fail Fleet::Error,
          "Job state '#{target_state}' could not be achieved"
      end
    end

    def underscore(camel_cased_word)
      return camel_cased_word unless camel_cased_word =~ /[A-Z-]|::/
      word = camel_cased_word.gsub(/([a-z\d])([A-Z])/,'\1_\2')
      word.tr!("-", "_")
      word.downcase!
      word
    end
  end
end