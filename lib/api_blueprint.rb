require 'rspec'
require 'rspec/core/formatters/base_text_formatter'

class ApiBlueprint < RSpec::Core::Formatters::BaseTextFormatter
  VERSION = "0.1.0"
  RSpec::Core::Formatters.register self, :example_passed, :example_started, :stop

  def initialize(output)
    super
    @passed_examples = {}
    @group_level = 0
  end

  def example_started(notification)
    @example_group_instance = notification.example.example_group_instance
  end

  def example_passed(passed)
    metadata = passed.example.metadata

    if metadata[:apidoc] &&
        metadata[:resource_group] &&
        metadata[:resource] &&
        metadata[:action] &&
        metadata[:action_description]

      request = @example_group_instance.request
      response = @example_group_instance.response
      description = description_array_from(passed.example.metadata).reverse.join(' ').gsub(/[\(\)]/, '..')

      @passed_examples.deep_merge!({
        metadata[:resource_group] => {
          metadata[:resource] => {
            metadata[:action] => {
              description: metadata[:action_description],
              examples: {
                description => {
                  request: {
                    parameters: JSON.pretty_generate(request.parameters.except(*request.path_parameters.keys.map(&:to_s))),
                    format: request.format
                  },
                  source: passed.example.instance_variable_get(:@example_block).source,
                  location: metadata[:location],
                  response: {
                    status: response.status,
                    body: response.body
                  },
                  uri_parameters: metadata[:action_uri_parameters]
                }
              }
            }
          }
        }
      })
    end
    @example_group_instance = nil
  end

  def message(notification)
  end

  def dump_summary(notification)
  end

  def stop(notification)
    @passed_examples.sort_by { |k,v| k }.each do |resource_group_name, resource_group_resources|
      print_resource_group(resource_group_name, resource_group_resources)
    end
  end

  private

  def print_resource_group(resource_group_name, resource_group_resources)
    output.puts "# Group #{resource_group_name}"
    resource_group_resources.each &method(:print_resource)
  end

  def print_resource(resource_name, actions)
    unless resource_name =~ /^[^\[\]]*\[\/[^\]]+\]/
      raise "resoure: '#{resource_name}' is invalid. :resource needs to be specified according to https://github.com/apiaryio/api-blueprint/blob/master/API%20Blueprint%20Specification.md#resource-section"
    end
    output.puts "# #{resource_name}"

    http_verbs = actions.keys.map {|action| action.scan(/\[([A-Z]+)\]/).flatten[0] }

    unless http_verbs.length == http_verbs.uniq.length
      raise "Action HTTP verbs are not unique #{actions.keys.inspect} for resource: '#{resource_name}'"
    end

    actions.each &method(:print_action)
  end

  def print_action(action_name, action_meta_data)
    output.puts "## #{action_name}\n" \
                "\n" \
                "#{action_meta_data[:description]}\n" \
                "#{RSpec.configuration.api_blueprint_body}\n" \
                "\n" \

    action_meta_data[:examples].each &method(:print_example)
  end

  def print_example(example_description, example_metadata)

    # Hack Hack Hack
    unless example_metadata[:uri_parameters].nil?
      output.puts "+ Parameters\n" \
       "\n" 
      example_metadata[:uri_parameters].each do |key, value|
        output.puts "    + #{key}: `#{value}`"
      end
    end
    # Hack Hack Hack

    output.puts "+ Request #{example_description}\n" \
      "\n" \
      "#{indent_lines(8, example_metadata[:request][:parameters])}\n" 

    output.puts "+ Response #{example_metadata[:response][:status]} (#{example_metadata[:request][:format]})\n" \
      "\n" \
      "        #{example_metadata[:response][:body]}\n" \
      "\n"
  end

  # To include the descriptions of all the contexts that are below the action
  # group, but not including resource/resource_group descriptions
  def description_array_from(example_metadata)
    parent = example_metadata[:parent_example_group] if example_metadata.key?(:parent_example_group)
    parent ||= example_metadata[:example_group] if example_metadata.key?(:example_group)
    if parent[:action].nil?
      []
    else
      [example_metadata[:description]] + description_array_from(parent)
    end
  end

  def indent_lines(number_of_spaces, string)
    string
      .split("\n")
      .map { |a| a.prepend(' ' * number_of_spaces) }
      .join("\n")
  end
end
